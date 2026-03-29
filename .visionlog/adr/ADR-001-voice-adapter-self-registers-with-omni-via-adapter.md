---
id: "ADR-001"
type: "decision"
title: "Voice adapter self-registers with omni via adapters.d/ manifest"
status: "accepted"
date: "2026-03-29"
relates_to: ["GOAL-001"]
---

## Decision
Eidos Assistant writes a manifest to ~/.config/eidosomni/adapters.d/voice.json on first launch. The manifest points to the voice adapter bundled inside the .app. Omni discovers it automatically. Users configure nothing.

## Key design points
- Bucket structure (recordings/{uuid}/audio.wav, transcript.json, classification.json) is the data contract
- Manifest is a discovery hint, not a dependency — app works without omni
- Adapter code lives in the .app bundle, not in omni's repo
- Self-healing: re-registers on every launch if path changed
