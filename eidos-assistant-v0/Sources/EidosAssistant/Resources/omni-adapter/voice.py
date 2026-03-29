"""
Eidos Omni Voice Adapter

Indexes voice recording buckets from eidos-assistant as omni resources.
Each bucket is a directory containing:
  audio.wav, transcript.json, classification.json (optional), context.json (future)

The adapter reads manifest.jsonl for fast discovery (no directory scanning).
Watermark-based sync — only processes buckets newer than last sync.

URI scheme: voice://{uuid}
Source: "voice"
"""

import hashlib
import json
import logging
from datetime import datetime
from pathlib import Path

from omni.adapters.base import AdapterBase, SyncResult
from omni.db.queries import get_resource_by_uri
from omni.worker.queue import enqueue
from omni.db.kv import kv_get, kv_set

logger = logging.getLogger(__name__)

VOICE_STORE = Path.home() / "Library/Application Support/eidos-assistant/voice"
RECORDINGS = VOICE_STORE / "recordings"
MANIFEST = VOICE_STORE / "manifest.jsonl"
WATERMARK_KEY = "voice_adapter_watermark"


class VoiceAdapter(AdapterBase):
    name = "voice"
    uri_prefix = "voice://"
    sync_interval = 60  # 1 minute

    async def sync(self) -> SyncResult:
        """Read manifest.jsonl, enqueue recording buckets newer than watermark."""
        result = SyncResult()

        if not MANIFEST.exists():
            return result

        watermark = await kv_get(WATERMARK_KEY) or ""
        new_watermark = watermark

        try:
            lines = MANIFEST.read_text().strip().split("\n")
        except Exception as e:
            logger.error(f"Failed to read manifest: {e}")
            result.errors += 1
            return result

        # Deduplicate manifest entries — keep latest status per uuid
        seen_uuids = set()
        entries = []
        for line in reversed(lines):
            try:
                entry = json.loads(line)
                uuid = entry.get("uuid", "")
                if uuid and uuid not in seen_uuids:
                    seen_uuids.add(uuid)
                    entries.append(entry)
            except json.JSONDecodeError:
                continue
        entries.reverse()

        for entry in entries:
            uuid = entry.get("uuid", "")
            ts = entry.get("timestamp", "")

            if not uuid or not ts:
                continue

            if ts <= watermark:
                result.skipped += 1
                continue

            bucket = RECORDINGS / uuid
            transcript_path = bucket / "transcript.json"

            # Need at least transcript.json to be indexable
            if not transcript_path.exists():
                result.skipped += 1
                continue

            uri = f"voice://{uuid}"

            # Compute content hash from transcript + classification
            try:
                content = transcript_path.read_text()
                classification_path = bucket / "classification.json"
                if classification_path.exists():
                    content += classification_path.read_text()
                content_hash = hashlib.sha256(content.encode()).hexdigest()
            except Exception as e:
                logger.error(f"Failed to hash bucket {uuid}: {e}")
                result.errors += 1
                continue

            # Check if already indexed with same hash
            existing = await get_resource_by_uri(uri)
            if existing and existing.content_hash == content_hash:
                result.skipped += 1
                if ts > new_watermark:
                    new_watermark = ts
                continue

            # Enqueue for worker pipeline
            await enqueue(uri, "voice", "index", payload={
                "uuid": uuid,
                "content_hash": content_hash,
                "bucket_path": str(bucket),
            })
            result.enqueued += 1

            if ts > new_watermark:
                new_watermark = ts

        if new_watermark > watermark:
            await kv_set(WATERMARK_KEY, new_watermark)

        if result.enqueued > 0:
            logger.info(f"Voice sync: {result.enqueued} enqueued, {result.skipped} skipped")

        return result

    async def read_content(self, uri: str) -> dict:
        """Read bucket contents for the worker pipeline to chunk and embed."""
        uuid = uri.removeprefix("voice://")
        bucket = RECORDINGS / uuid

        # Read transcript
        transcript_path = bucket / "transcript.json"
        if not transcript_path.exists():
            return {"text": "", "metadata": {"error": "no transcript"}}

        transcript = json.loads(transcript_path.read_text())

        # Read classification (optional — daemon may not have run yet)
        classification = {}
        classification_path = bucket / "classification.json"
        if classification_path.exists():
            classification = json.loads(classification_path.read_text())

        # Read context (future — screen focus, active app)
        context = {}
        context_path = bucket / "context.json"
        if context_path.exists():
            context = json.loads(context_path.read_text())

        # Audio file info
        audio_path = bucket / "audio.wav"
        byte_size = audio_path.stat().st_size if audio_path.exists() else None

        # Determine resource_at from transcript timestamp
        resource_at = None
        transcribed_at = transcript.get("transcribed_at")
        if transcribed_at:
            try:
                resource_at = datetime.fromisoformat(transcribed_at)
            except (ValueError, TypeError):
                pass

        category = classification.get("category", "unclassified")
        title = f"Voice note — {category}"
        if classification.get("metadata", {}).get("topic"):
            title = f"Voice note — {classification['metadata']['topic']}"

        return {
            "text": transcript.get("text", ""),
            "title": title,
            "mime_type": "audio/wav",
            "resource_at": resource_at,
            "metadata": {
                # Classification
                "category": category,
                "classification_metadata": classification.get("metadata", {}),
                "confidence": classification.get("confidence"),
                "classifier": classification.get("classifier"),
                # Transcript
                "duration_sec": transcript.get("duration_sec"),
                "model": transcript.get("model"),
                "language": transcript.get("language"),
                "word_count": transcript.get("word_count"),
                "segment_count": len(transcript.get("segments", [])),
                # Audio
                "audio_path": str(audio_path) if audio_path.exists() else None,
                "byte_size": byte_size,
                # Bucket
                "bucket_path": str(bucket),
                "uuid": uuid,
                # Context (future)
                **({f"context_{k}": v for k, v in context.items()} if context else {}),
            },
        }
