---
id: "GOAL-001"
type: "goal"
title: "Eidos Assistant is a front-end for omni, not a standalone app"
status: "active"
date: "2026-03-29"
depends_on: []
unlocks: []
---

The app captures voice → classifies via daemon → writes structured JSONL to disk. Omni indexes it. The app never pushes to omni. Categories (task, reminder, shopping, idea) are tags in omni, not destinations. Apps are views filtered by category. One store, many views.
