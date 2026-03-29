#!/usr/bin/env python3
"""
eidos-assistant-daemon — Intelligence layer for Eidos Assistant.

Classifies voice notes and writes classification.json into recording buckets.
Omni indexes these buckets as source "voice" via the voice adapter.

Bucket structure (written by app + daemon together):
  voice/recordings/{uuid}/
    audio.wav              ← app writes
    transcript.json        ← app writes
    classification.json    ← daemon writes (this file)

Uses Claude Agent SDK for classification.
"""

import asyncio
import json
import os
import socket
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path

from claude_agent_sdk import (
    ClaudeAgentOptions,
    ClaudeSDKClient,
    tool,
    create_sdk_mcp_server,
)

SOCKET_PATH = "/tmp/eidos-assistant.sock"
VOICE_STORE = Path.home() / "Library/Application Support/eidos-assistant/voice"
RECORDINGS = VOICE_STORE / "recordings"
MANIFEST = VOICE_STORE / "manifest.jsonl"
DAEMON_PID = Path.home() / "Library/Application Support/eidos-assistant/daemon.pid"


def write_classification(uuid: str, category: str, confidence: float, metadata: dict):
    """Write classification.json into the recording bucket."""
    bucket = RECORDINGS / uuid
    if not bucket.exists():
        print(f"Warning: bucket {uuid} not found, creating")
        bucket.mkdir(parents=True, exist_ok=True)

    classification = {
        "category": category,
        "confidence": confidence,
        "metadata": metadata,
        "classified_at": datetime.now(timezone.utc).isoformat(),
        "classifier": "claude-agent-sdk",
        "version": 1,
    }
    (bucket / "classification.json").write_text(json.dumps(classification, indent=2))

    # Update manifest status
    append_manifest(uuid, "classified")

    return classification


def append_manifest(uuid: str, status: str):
    """Append a status line to manifest.jsonl."""
    entry = {
        "uuid": uuid,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "status": status,
    }
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    with open(MANIFEST, "a") as f:
        f.write(json.dumps(entry) + "\n")


# ── Classification Tools ─────────────────────────────────────────
# Each tool writes classification.json into the bucket.
# The tool receives the uuid so it knows which bucket to write to.

_current_uuid = ""  # Set per-request before agent runs


@tool("classify_reminder", "Voice note is a reminder with timing", {"text": str, "due_hint": str})
async def classify_reminder(args):
    c = write_classification(_current_uuid, "reminder", 0.9, {"due_hint": args.get("due_hint", "")})
    return {"content": [{"type": "text", "text": f"Classified as reminder"}]}


@tool("classify_task", "Voice note is an actionable task", {"text": str, "priority": str, "project": str})
async def classify_task(args):
    c = write_classification(_current_uuid, "task", 0.9, {
        "priority": args.get("priority", "medium"), "project": args.get("project", ""),
    })
    return {"content": [{"type": "text", "text": f"Classified as task"}]}


@tool("classify_devlog", "Voice note is a technical/debugging insight", {"text": str, "tags": str})
async def classify_devlog(args):
    c = write_classification(_current_uuid, "devlog", 0.9, {"tags": args.get("tags", "")})
    return {"content": [{"type": "text", "text": f"Classified as devlog"}]}


@tool("classify_message", "Voice note is a message to draft for someone", {"text": str, "recipient": str})
async def classify_message(args):
    c = write_classification(_current_uuid, "message", 0.9, {"recipient": args.get("recipient", "")})
    return {"content": [{"type": "text", "text": f"Classified as message"}]}


@tool("classify_knowledge", "Voice note is a fact, decision, or learning", {"text": str, "topic": str})
async def classify_knowledge(args):
    c = write_classification(_current_uuid, "knowledge", 0.9, {"topic": args.get("topic", "general")})
    return {"content": [{"type": "text", "text": f"Classified as knowledge"}]}


@tool("classify_idea", "Voice note is a creative idea or brainstorm", {"text": str, "domain": str})
async def classify_idea(args):
    c = write_classification(_current_uuid, "idea", 0.9, {"domain": args.get("domain", "")})
    return {"content": [{"type": "text", "text": f"Classified as idea"}]}


@tool("classify_todo", "Voice note is a personal to-do item", {"text": str, "context": str})
async def classify_todo(args):
    c = write_classification(_current_uuid, "todo", 0.9, {"context": args.get("context", "personal")})
    return {"content": [{"type": "text", "text": f"Classified as todo"}]}


@tool("classify_shopping", "Voice note is a shopping list item", {"text": str, "store": str})
async def classify_shopping(args):
    c = write_classification(_current_uuid, "shopping", 0.9, {"store": args.get("store", "")})
    return {"content": [{"type": "text", "text": f"Classified as shopping"}]}


# ── Agent Config ─────────────────────────────────────────────────

TOOLS = [
    classify_reminder, classify_task, classify_devlog, classify_message,
    classify_knowledge, classify_idea, classify_todo, classify_shopping,
]

ROUTER_SERVER = create_sdk_mcp_server(name="eidos-router", version="0.1.0", tools=TOOLS)

SYSTEM_PROMPT = """You classify voice notes for the eidos omni ecosystem. Call exactly ONE tool.

Rules:
- "remind me", dates/times, deadlines → classify_reminder
- work items: "fix", "build", "ship", "deploy", "need to" → classify_task
- technical: debugging, architecture, code → classify_devlog
- "tell X", "message X", "let X know" → classify_message
- facts, decisions, learnings → classify_knowledge
- creative: "what if", brainstorms → classify_idea
- personal errands: "pick up", "call", "schedule" → classify_todo
- "buy", groceries, shopping → classify_shopping
- Ambiguous → classify_knowledge

Extract useful metadata (tags, priority, recipient, store name, due date hints).
Be decisive."""


async def classify_note(text: str, uuid: str) -> dict:
    """Classify a voice note and write classification.json into its bucket."""
    global _current_uuid
    _current_uuid = uuid

    options = ClaudeAgentOptions(
        system_prompt=SYSTEM_PROMPT,
        mcp_servers={"router": ROUTER_SERVER},
        allowed_tools=[f"mcp__router__{t.name}" for t in TOOLS],
        max_turns=2,
    )

    result_text = ""
    try:
        async with ClaudeSDKClient(options=options) as client:
            await client.query(f"Classify this voice note:\n\n{text}")
            async for msg in client.receive_response():
                if hasattr(msg, "content"):
                    result_text = str(msg.content)
    except Exception as e:
        # Fallback: classify as knowledge
        write_classification(uuid, "knowledge", 0.3, {"topic": "unrouted", "error": str(e)[:200]})
        return {"classified": "knowledge", "fallback": True, "error": str(e)[:200]}

    # Read back what was written
    bucket = RECORDINGS / uuid
    classification_path = bucket / "classification.json"
    if classification_path.exists():
        classification = json.loads(classification_path.read_text())
        return {"classified": classification["category"], "uuid": uuid}
    else:
        return {"classified": "unknown", "uuid": uuid, "response": result_text[:200]}


# ── Socket Server ────────────────────────────────────────────────

def handle_client(conn, loop):
    try:
        data = b""
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
            if b"\n" in data:
                break
        if data:
            note = json.loads(data.decode())
            text = note.get("text", "")
            uuid = note.get("uuid", "")
            if text.strip() and uuid:
                future = asyncio.run_coroutine_threadsafe(classify_note(text, uuid), loop)
                result = future.result(timeout=60)
            elif text.strip():
                # No uuid — create a bucket for it
                uuid = datetime.now().strftime("%Y%m%d%H%M%S")
                bucket = RECORDINGS / uuid
                bucket.mkdir(parents=True, exist_ok=True)
                future = asyncio.run_coroutine_threadsafe(classify_note(text, uuid), loop)
                result = future.result(timeout=60)
            else:
                result = {"error": "empty note"}
            conn.sendall(json.dumps(result).encode() + b"\n")
    except Exception as e:
        try:
            conn.sendall(json.dumps({"error": str(e)}).encode() + b"\n")
        except:
            pass
    finally:
        conn.close()


def run_socket_server(loop):
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    server.listen(5)
    os.chmod(SOCKET_PATH, 0o700)
    print(f"Listening on {SOCKET_PATH}")
    try:
        while True:
            conn, _ = server.accept()
            t = threading.Thread(target=handle_client, args=(conn, loop), daemon=True)
            t.start()
    except KeyboardInterrupt:
        pass
    finally:
        server.close()
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)


# ── Main ─────────────────────────────────────────────────────────

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--test":
        text = " ".join(sys.argv[2:]) if len(sys.argv) > 2 else input("Note: ")
        uuid = f"test-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        (RECORDINGS / uuid).mkdir(parents=True, exist_ok=True)
        result = asyncio.run(classify_note(text, uuid))
        print(json.dumps(result, indent=2))
        # Show what was written
        cpath = RECORDINGS / uuid / "classification.json"
        if cpath.exists():
            print(f"\n--- classification.json ---")
            print(cpath.read_text())
        return

    if len(sys.argv) > 1 and sys.argv[1] == "--stop":
        if DAEMON_PID.exists():
            os.kill(int(DAEMON_PID.read_text()), 15)
            print("Stopped")
        else:
            print("Not running")
        return

    if len(sys.argv) > 1 and sys.argv[1] == "--stats":
        if not RECORDINGS.exists():
            print("No recordings"); return
        buckets = [d for d in RECORDINGS.iterdir() if d.is_dir()]
        classified = sum(1 for b in buckets if (b / "classification.json").exists())
        cats = {}
        for b in buckets:
            cp = b / "classification.json"
            if cp.exists():
                c = json.loads(cp.read_text())
                cat = c.get("category", "unknown")
                cats[cat] = cats.get(cat, 0) + 1
        print(f"Buckets: {len(buckets)} ({classified} classified)")
        for cat, n in sorted(cats.items(), key=lambda x: -x[1]):
            print(f"  {cat}: {n}")
        return

    with open(DAEMON_PID, "w") as f:
        f.write(str(os.getpid()))

    print(f"eidos-assistant-daemon (PID: {os.getpid()})")
    print(f"Writes classification.json into voice/recordings/{{uuid}}/")
    print(f"Omni indexes via voice adapter")

    loop = asyncio.new_event_loop()
    threading.Thread(target=loop.run_forever, daemon=True).start()
    try:
        run_socket_server(loop)
    finally:
        loop.call_soon_threadsafe(loop.stop)
        DAEMON_PID.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
