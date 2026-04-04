---
id: '0001'
title: Omni adapter pattern is directory-per-recording compatible
status: open
evidence: VERIFIED
sources: 1
created: '2026-03-29'
---

## Claim

Omni's resource model (uri, source, resource_type, content_hash, metadata JSON, resource_at) supports the bucket-per-recording pattern. Each recording directory becomes one resource with URI voice://{uuid}. The adapter's read_content() returns the transcript text for embedding while metadata carries classification, duration, model, and audio_path. The audio.wav stays on disk — omni doesn't need to ingest it, just index the transcript and point to the audio. Chunks are created from the transcript text. The bucket directory structure (audio.wav, transcript.json, classification.json, context.json) is invisible to omni — the adapter abstracts it into one resource.

## Supporting Evidence

> **Evidence: [VERIFIED]** — Direct code review of eidosomni/src/omni/adapters/base.py, db/models.py, adapters/filesystem.py, adapters/tosh.py, retrieved 2026-03-29

## Caveats

None identified yet.
