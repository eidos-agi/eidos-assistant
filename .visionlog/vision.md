---
title: "Eidos Assistant: Front-End for Eidos Omni"
type: "vision"
date: "2026-03-29"
---

## Vision

Eidos Assistant is a front-end for eidos omni — the universal life index. It is the primary human interface for getting things into and out of omni via voice.

## What This Means

Omni is the storage standard. It indexes a person's entire digital life: files, messages, emails, photos, browser history, Claude sessions, terminal history, screen focus, and now voice. Eidos Assistant is how a human talks to omni.

**Input:** Hold a key, speak, release. The daemon classifies and stores the note in omni's voice source. Omni indexes it alongside everything else.

**Output (future):** Ask omni questions by voice. "What did I decide about the API design?" Omni searches across all sources — voice, files, messages, code — and answers.

## Architecture

1. **Mac app** — capture layer. PTT recording, Whisper transcription, local display.
2. **Daemon** — intelligence layer. Claude Agent SDK classifies each note (reminder, task, devlog, message, knowledge, idea, todo, shopping) and writes to omni's voice store.
3. **Omni** — the standard. One store, many views. Categories are tags, not destinations. Apps are filtered views into omni.

## Principles

- Everything stays in eidos. No Apple services, no external routing.
- Omni is the single source of truth. The app is a front-end.
- Categories expand as life expands: tasks, shopping, reminders, ideas — all just tags in omni.
- Voice notes correlate with everything else by timestamp and semantics.
- Capture latency is the product. Sub-second from thought to stored.

## Roadmap

- Omni source registration: voice/notes.jsonl becomes a first-class omni source
- Screen focus correlation: what were you looking at when you said it
- Resume-resume: surface unfinished Claude Code sessions
- Voice query: ask omni questions out loud, get answers
- Ideas → action: voice ideas flow through ike.md into executed work
