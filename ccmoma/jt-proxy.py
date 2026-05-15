#!/usr/bin/env python3
"""本地代理：Claude Code (Anthropic) → 九天 (OpenAI) 格式转换"""

import http.server
import json
import sys
import urllib.request
import urllib.error

TARGET = "https://jiutian.10086.cn/largemodel/moma/api/v3"
PORT = 8976


def extract_text(content):
    """从 Anthropic content 格式提取纯文本"""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict) and item.get("type") == "text":
                parts.append(item.get("text", ""))
        return "\n".join(parts)
    return str(content)


def anthropic_to_openai(body):
    """将 Anthropic /messages 请求转为 OpenAI /chat/completions 格式"""
    model = body.get("model", "moonshotai/kimi-k2.6")
    max_tokens = body.get("max_tokens", 8192)
    stream = body.get("stream", False)

    system = body.get("system")
    openai_msgs = []
    if system:
        openai_msgs.append({"role": "system", "content": extract_text(system)})

    # tools → function calling
    tools = body.get("tools")
    openai_tools = None
    if tools:
        openai_tools = []
        for t in tools:
            openai_tools.append({
                "type": "function",
                "function": {
                    "name": t.get("name", ""),
                    "description": t.get("description", ""),
                    "parameters": t.get("input_schema", {}),
                }
            })

    for m in body.get("messages", []):
        role = m.get("role", "user")
        content = m.get("content", "")

        # tool_use / tool_result
        if role == "assistant" and isinstance(content, list):
            text_parts = []
            tool_calls = []
            for item in content:
                if item.get("type") == "text":
                    text_parts.append(item.get("text", ""))
                elif item.get("type") == "tool_use":
                    tool_calls.append({
                        "id": item.get("id", ""),
                        "type": "function",
                        "function": {
                            "name": item.get("name", ""),
                            "arguments": json.dumps(item.get("input", {})),
                        }
                    })
            msg = {"role": "assistant", "content": "\n".join(text_parts) if text_parts else None}
            if tool_calls:
                msg["tool_calls"] = tool_calls
            openai_msgs.append(msg)
        elif role == "user" and isinstance(content, list):
            has_tool_result = any(item.get("type") == "tool_result" for item in content)
            if has_tool_result:
                for item in content:
                    if item.get("type") == "tool_result":
                        openai_msgs.append({
                            "role": "tool",
                            "tool_call_id": item.get("tool_use_id", ""),
                            "content": extract_text(item.get("content", "")),
                        })
                    elif item.get("type") == "text":
                        openai_msgs.append({"role": "user", "content": item.get("text", "")})
            else:
                openai_msgs.append({"role": "user", "content": extract_text(content)})
        else:
            openai_msgs.append({"role": role, "content": extract_text(content)})

    result = {
        "model": model,
        "messages": openai_msgs,
        "max_tokens": max_tokens,
        "stream": stream,
    }
    if openai_tools:
        result["tools"] = openai_tools
    return result


def openai_to_anthropic(resp_data):
    """将 OpenAI 非流式响应转回 Anthropic 格式"""
    choice = resp_data.get("choices", [{}])[0]
    msg = choice.get("message", {})
    usage = resp_data.get("usage", {})

    content_text = msg.get("content") or ""
    stop_reason = choice.get("finish_reason", "stop")
    anthropic_stop = {
        "stop": "end_turn",
        "length": "max_tokens",
        "tool_calls": "tool_use",
    }.get(stop_reason, "end_turn")

    content = [{"type": "text", "text": content_text}]

    # tool_calls → tool_use blocks
    if msg.get("tool_calls"):
        for tc in msg["tool_calls"]:
            try:
                inp = json.loads(tc["function"]["arguments"])
            except Exception:
                inp = {}
            content.append({
                "type": "tool_use",
                "id": tc.get("id", ""),
                "name": tc["function"]["name"],
                "input": inp,
            })

    return {
        "id": resp_data.get("id", ""),
        "type": "message",
        "role": "assistant",
        "content": content,
        "model": resp_data.get("model", ""),
        "stop_reason": anthropic_stop,
        "usage": {
            "input_tokens": usage.get("prompt_tokens", 0),
            "output_tokens": usage.get("completion_tokens", 0),
        },
    }


def stream_openai_to_anthropic(line):
    """将 OpenAI 流式 chunk 转为 Anthropic SSE 事件"""
    if not line.startswith("data: "):
        return None
    data = line[6:].strip()
    if data == "[DONE]":
        return "event: message_stop\ndata: {}\n\n"

    try:
        chunk = json.loads(data)
    except Exception:
        return None

    choices = chunk.get("choices", [])
    if not choices:
        return None

    delta = choices[0].get("delta", {})
    finish_reason = choices[0].get("finish_reason")

    # message_start (first chunk with role)
    if delta.get("role"):
        return (
            "event: message_start\n"
            f'data: {json.dumps({"type": "message_start", "message": {"id": chunk.get("id", ""), "type": "message", "role": "assistant", "content": [], "model": chunk.get("model", ""), "stop_reason": None, "usage": {"input_tokens": 0, "output_tokens": 0}}})}\n\n'
        )

    # content_delta
    content = delta.get("content", "")
    if content:
        return (
            "event: content_block_delta\n"
            f'data: {json.dumps({"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": content}})}\n\n'
        )

    # finish
    if finish_reason:
        anthropic_stop = {
            "stop": "end_turn",
            "length": "max_tokens",
            "tool_calls": "tool_use",
        }.get(finish_reason, "end_turn")
        return (
            "event: message_delta\n"
            f'data: {json.dumps({"type": "message_delta", "delta": {"stop_reason": anthropic_stop, "stop_sequence": None}, "usage": {"output_tokens": 0}})}\n\n'
        )

    return None


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""

        # 从 Authorization: Bearer 或 x-api-key 获取 token
        api_key = ""
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Bearer "):
            api_key = auth[7:]
        if not api_key:
            api_key = self.headers.get("x-api-key", "")

        try:
            req_json = json.loads(body)
        except Exception:
            self.send_response(400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Invalid JSON body"}).encode())
            return

        is_stream = req_json.get("stream", False)
        openai_body = anthropic_to_openai(req_json)

        url = TARGET + "/chat/completions"
        req = urllib.request.Request(url, data=json.dumps(openai_body).encode(), method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("Authorization", f"Bearer {api_key}")

        if is_stream:
            self._handle_stream(req)
        else:
            self._handle_non_stream(req)

    def _handle_non_stream(self, req):
        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                resp_data = json.loads(resp.read())
                anthropic_resp = openai_to_anthropic(resp_data)
                resp_bytes = json.dumps(anthropic_resp).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(resp_bytes)))
                self.end_headers()
                self.wfile.write(resp_bytes)
        except urllib.error.HTTPError as e:
            err_body = e.read()
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(err_body)
        except Exception as e:
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def _handle_stream(self, req):
        try:
            resp = urllib.request.urlopen(req, timeout=300)
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()

            # message_start
            first_event = True
            for raw_line in resp:
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                if first_event:
                    # 发送 message_start
                    try:
                        chunk = json.loads(line[6:] if line.startswith("data: ") else line)
                        msg_id = chunk.get("id", "")
                        model = chunk.get("model", "")
                    except Exception:
                        msg_id, model = "", ""
                    self.wfile.write(
                        "event: message_start\n"
                        f'data: {json.dumps({"type":"message_start","message":{"id":msg_id,"type":"message","role":"assistant","content":[],"model":model,"stop_reason":None,"usage":{"input_tokens":0,"output_tokens":0}}})}\n\n'
                    )
                    # content block start
                    self.wfile.write(
                        "event: content_block_start\n"
                        f'data: {json.dumps({"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}})}\n\n'
                    )
                    self.wfile.flush()
                    first_event = False

                evt = stream_openai_to_anthropic(line)
                if evt:
                    self.wfile.write(evt.encode())
                    self.wfile.flush()

            self.wfile.write("event: message_stop\ndata: {}\n\n".encode())
            self.wfile.flush()
        except urllib.error.HTTPError as e:
            err = e.read().decode("utf-8", errors="replace")
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(err.encode())
        except Exception as e:
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else PORT
    server = http.server.HTTPServer(("127.0.0.1", port), ProxyHandler)
    print(f"jt-proxy 已启动: http://127.0.0.1:{port} → {TARGET}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
