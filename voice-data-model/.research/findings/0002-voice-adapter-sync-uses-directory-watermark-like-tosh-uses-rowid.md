---
id: '0002'
title: Voice adapter sync uses directory watermark like tosh uses rowid
status: open
evidence: VERIFIED
sources: 1
created: '2026-03-29'
---

## Claim

Tosh adapter maintains a rowid watermark in omni_kv. Voice adapter should maintain a timestamp or UUID watermark — scan voice/recordings/ for directories newer than watermark, enqueue each as a resource. sync_interval of 60s is appropriate (matches filesystem). No push needed — omni pulls on schedule. SyncResult tracks enqueued/skipped/errors.

## Supporting Evidence

> **Evidence: [VERIFIED]** — eidosomni/src/omni/adapters/tosh.py watermark pattern, scheduler.py sync loop, retrieved 2026-03-29

## Caveats

None identified yet.
