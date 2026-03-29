# 100 Performance Improvements — Eidos Assistant

## Priority: Do First (high impact, low effort)
1. whisper.cpp instead of Python — eliminates 100MB+ Python runtime
2. Keep whisper model warm in daemon — no reload per transcription
8. Preload model on app launch
19. Profile actual bottleneck (model load vs inference)
28. Debounce <0.5s recordings (PTT accidents)
44. Profile SwiftUI redraws with _printChanges()
48. Split NoteStore into recording state vs note data
56. Instrument with leaks/vmmap
57. Profile with Instruments Allocations
66. Add memory tracking to autotest.sh
88. Verify zero CPU when idle
97. Memory regression test in CI

## A. Whisper/Transcription (1-20)
1. whisper.cpp instead of Python whisper — H/M
2. Keep model warm in daemon — H/L
3. whisper.cpp CoreML for Apple Neural Engine — H/M
4. Quantize to int4 — M/L
5. Auto-select tiny.en for <5s recordings — M/L
6. Stream audio during recording — H/H
7. Cache model in shared memory (mmap) — M/M
8. Preload model on launch — M/L
9. VAD to trim silence before transcription — M/L
10. Parallel chunk transcription — M/H
11. beam_size=1 for speed (3x faster, ~2% accuracy drop) — M/L
12. batch_size > 1 — L/L
13. Metal GPU acceleration — H/H
14. Condition on previous text for continuation — L/L
15. Skip silence detection threshold — L/L
16. Disable word timestamps — L/L
17. Tiny model pre-check before large model — M/M
18. CTranslate2 Apple Silicon optimizations — M/M
19. Profile: model load vs inference time — H/L
20. Apple SFSpeechRecognizer for <3s clips — M/M

## B. Audio Recording (21-35)
21. AVAudioEngine instead of AVAudioRecorder — M/M
22. Record to memory buffer, not temp file — M/M
23. Circular buffer for "what did I just say" — H/H
24. 8kHz sample rate for voice — L/L
25. OPUS/AAC compression instead of WAV — M/L
26. Pre-allocate audio buffer — L/L
27. Zero-copy audio to whisper — M/H
28. Debounce <0.5s recordings — M/L
29. Audio level gate (auto-stop on silence) — L/L
30. Reduce metering when not visible — L/L
31. Hardware-accelerated encoding — L/M
32. Profile AVAudioRecorder startup time — M/L
33. Reuse AVAudioRecorder instance — L/L
34. Skip Bluetooth codec overhead check — L/M
35. Monitor audio input dropout — L/L

## C. UI/SwiftUI (36-55)
36. Verify LazyVStack is actually lazy — M/L
37. Throttle @Published to 4Hz — M/L
38. .drawingGroup() on level meter — L/L
39. Remove .textSelection from list items — L/L
40. Paginate notes (50 at a time) — M/L
41. Debounce search (200ms) — M/L
42. Cache day grouping — L/L
43. EquatableView for note rows — M/L
44. Profile with _printChanges() — H/L
45. AppKit-only floating panel — M/M
46. Remove shadow from pill — L/L
47. Audit @ObservedObject usage — L/L
48. Split recording state from note data — M/M
49. Pre-render menu bar icon — L/L
50. Single context menu at list level — L/L
51. Profile NSHostingView memory — M/L
52. TimelineView for timer — L/L
53. Reduce floating panel size — L/L
54. Don't animate level bars — L/L
55. Profile MenuBarExtra memory — M/L

## D. Memory (56-70)
56. leaks + vmmap profiling — H/L
57. Instruments Allocations — H/L
58. Log RSS in PerformanceMonitor — M/L
59. MALLOC_NANO_ZONE=0 test — L/L
60. Aggressive AVAudioRecorder release — M/L
61. autoreleasepool around transcription — M/L
62. Cap in-memory notes at 200 — M/L
63. Compress old notes — L/M
64. Audit String copies — L/L
65. Weak references in all closures — M/L
66. RSS tracking in autotest — M/L
67. Dynamic MemoryGuard limit — L/L
68. Memory pressure responder — M/M
69. Pool temp file URLs — L/L
70. Audit DispatchSource lifecycle — M/L

## E. Disk I/O (71-80)
71. SQLite instead of JSON — M/M
72. Debounce saves (500ms) — M/L
73. Memory-mapped notes file — L/M
74. Async file I/O — M/L
75. Verify temp file cleanup — L/L
76. Rotate metrics.jsonl at 10K lines — L/L
77. Binary metrics encoding — L/M
78. Profile disk write latency — L/L
79. FileHandle.write for appends — L/L
80. Lazy-load notes on launch — M/L

## F. Process/System (81-90)
81. Measure app launch time — M/L
82. Defer non-critical init — M/L
83. @_eagerMove on large structs — L/L
84. -Osize for smaller binary — L/L
85. Strip debug symbols — L/L
86. LTO (link-time optimization) — L/L
87. Profile energy impact — M/L
88. Verify zero CPU when idle — H/L
89. QoS .userInitiated for transcription — L/L
90. Audit thread count — M/L

## G. Network/Future (91-95)
91. Batch Supabase sync (5min intervals) — M/M
92. gzip payloads — L/L
93. Offline upload queue — M/M
94. Delta sync — M/H
95. CDN for model distribution — L/H

## H. Testing/Observability (96-100)
96. Instruments trace in CI — M/M
97. Memory regression test — H/L
98. Startup time regression test — M/L
99. Transcription speed alerting — M/L
100. Live metrics dashboard — M/M
