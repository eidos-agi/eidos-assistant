#!/usr/bin/env python3
"""
Fast Whisper transcription for Eidos Assistant.
Outputs full transcript JSON with segments for the recording bucket.
"""
import sys
import json
from datetime import datetime, timezone


def transcribe(audio_path: str, model_size: str = "large-v3-turbo"):
    from faster_whisper import WhisperModel

    model = WhisperModel(model_size, device="auto", compute_type="auto")
    segments_iter, info = model.transcribe(audio_path, language="en", beam_size=5)

    segments = []
    full_text_parts = []
    for seg in segments_iter:
        segments.append({
            "start": round(seg.start, 3),
            "end": round(seg.end, 3),
            "text": seg.text.strip(),
        })
        full_text_parts.append(seg.text.strip())

    full_text = " ".join(full_text_parts)

    result = {
        "text": full_text,
        "segments": segments,
        "language": info.language,
        "duration_sec": round(info.duration, 2),
        "model": model_size,
        "transcribed_at": datetime.now(timezone.utc).isoformat(),
        "word_count": len(full_text.split()),
    }

    print(json.dumps(result))


if __name__ == "__main__":
    audio_path = sys.argv[1]
    model_size = sys.argv[2] if len(sys.argv) > 2 else "large-v3-turbo"
    transcribe(audio_path, model_size)
