---
id: TASK-0001
title: Migrate CDD page to components (ContractChart, CompareTable, VideoEmbed)
status: To Do
created: '2026-03-29'
tags:
  - eidosagi.com
  - components
  - cleanup
---
CDD page has 32 lines of inline cdd-chart-* styles. ContractChart component was built but never wired. Replace all 3 contract/output/skill sections with ContractChart. Replace the grocery comparison with CompareTable. Replace inline video with VideoEmbed. Strip duplicate CSS.
