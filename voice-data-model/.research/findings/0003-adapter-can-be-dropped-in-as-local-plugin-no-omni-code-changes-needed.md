---
id: '0003'
title: Adapter can be dropped in as local plugin — no omni code changes needed
status: open
evidence: VERIFIED
sources: 1
created: '2026-03-29'
---

## Claim

Omni's 3-layer adapter loader auto-discovers .py files in ~/.local/share/eidosomni/adapters/. A voice.py file placed there is loaded on next startup. No changes to omni core required. This is the cleanest integration path — voice adapter ships with eidos-assistant, installs itself into the adapters directory.

## Supporting Evidence

> **Evidence: [VERIFIED]** — eidosomni/src/omni/adapters/__init__.py Layer 3 local scan logic, retrieved 2026-03-29

## Caveats

None identified yet.
