---
id: '0005'
title: Temporal correlation is built into omni via resource_at + delta tracking
status: open
evidence: VERIFIED
sources: 1
created: '2026-03-29'
---

## Claim

Every omni resource has resource_at (when it was created in the source) and created_at (when indexed). Deltas track change history with timestamps. omni_whats_changed searches by time range. This means voice notes with accurate timestamps automatically correlate with other sources (files edited, messages sent, pages browsed) in the same time window. No extra work needed — the temporal spine exists. Future screen focus context (context.json) would add another dimension but isn't required for correlation to work.

## Supporting Evidence

> **Evidence: [VERIFIED]** — db/models.py Delta model, api/routers/search.py whats_changed endpoint, mcp/tools.py omni_whats_changed tool, retrieved 2026-03-29

## Caveats

None identified yet.
