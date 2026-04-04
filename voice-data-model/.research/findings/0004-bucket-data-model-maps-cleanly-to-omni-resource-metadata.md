---
id: '0004'
title: Bucket data model maps cleanly to omni resource + metadata
status: open
evidence: VERIFIED
sources: 1
created: '2026-03-29'
---

## Claim

The bucket structure (voice/recordings/{uuid}/audio.wav, transcript.json, classification.json, context.json) maps to one omni resource: uri=voice://{uuid}, source="voice", resource_type=classification.category (or "voice_note"), metadata={category, due_hint, tags, priority, recipient, duration, model, audio_path, context}. read_content() reads transcript.json for text, classification.json for metadata, and returns the combined dict. The worker then chunks the transcript text and embeds it. Audio file path is stored in metadata for playback — omni doesn't embed audio, just indexes the text.

## Supporting Evidence

> **Evidence: [VERIFIED]** — Omni resource schema (db/models.py), worker pipeline (worker/pipeline.py), comparison with filesystem and tosh adapters, retrieved 2026-03-29

## Caveats

None identified yet.
