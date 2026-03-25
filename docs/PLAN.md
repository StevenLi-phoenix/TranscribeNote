# Notetaker Enhancement Plan

> Making Notetaker the most attractive macOS transcription app

## Round 1 — 2026-03-24

### AI-Powered Intelligence

- [ ] **Chat with Transcript** -- Add a conversational AI panel in SessionDetailView where users can ask questions about a session's transcript ("What did we decide about the deadline?", "Summarize the budget discussion"). Uses the already-configured LLM engine with transcript context injected as system prompt. This is table-stakes in 2026 -- Otter, Granola, Fireflies, and Jamie all offer it. The local-first angle means conversations never leave the machine.

- [ ] **Auto-Generated Action Items** -- After recording ends, automatically extract action items (tasks, decisions, follow-ups) from the transcript as a separate structured list with checkboxes. Store as a new `ActionItem` SwiftData model linked to the session. Users can mark items complete, assign due dates, and copy them as a task list. Fireflies and Fathom built their businesses on this.

- [ ] **Smart Auto-Tagging** -- Use the LLM to automatically generate 3-5 semantic tags for each session upon completion (e.g., "product-review", "1-on-1", "brainstorm", "hiring"). Store in the existing `RecordingSession.tags` array. Display as colored pills in SessionListView. Enable tag-based filtering in the sidebar. Transforms the session list from a chronological dump into an organized knowledge base.

- [ ] **AI Recipes (Custom Prompt Templates)** -- Inspired by Granola's Recipes: let users save reusable prompt templates for different meeting types (e.g., "Sprint Retro" extracts what went well / what didn't / action items; "Sales Call" extracts objections, next steps, pricing discussed; "Lecture Notes" produces study-guide format). Store as JSON in Application Support. Apply via a dropdown in the summary toolbar. This turns the LLM from a generic summarizer into a domain-specific assistant.

- [ ] **Cross-Session Knowledge Search** -- Add a global "Ask your notes" search bar (Cmd+Shift+F) that queries the LLM with context from ALL sessions, not just one. Uses RAG-style approach: full-text search narrows to relevant transcript chunks, then LLM synthesizes an answer with source session links. Otter's AI Chat across meetings is their stickiest feature -- this brings it local-first.

### UX Polish and Delight

- [ ] **Waveform Visualization with Seek** -- Replace the simple AudioLevelBar with a rendered waveform of the full recording in PlaybackControlView. Allow click-to-seek on the waveform. Highlight the currently-playing segment. Show transcript segments as colored regions on the waveform. This is the kind of polish that makes an app feel premium and justifies a price tag -- every serious audio app (Descript, Audacity, Voice Memos) has this.

- [ ] **Live Transcript Highlight During Playback** -- During audio playback in SessionDetailView, auto-scroll the transcript and highlight the currently-spoken segment in real-time (karaoke-style sync). Click any transcript segment to seek audio to that timestamp. The timestamp data already exists in `TranscriptSegment.startTime`/`endTime` -- this just wires it to the playback position. Transforms passive reading into active audio-text navigation.

- [ ] **Keyboard-First Power User Experience** -- Add comprehensive keyboard shortcuts: Space to play/pause, arrow keys to skip 5s/15s, Cmd+E to export, Cmd+K to open command palette (Raycast-style) for quick actions (search sessions, start recording, generate summary, copy transcript). Display shortcut hints in menus and tooltips. Power users expect this from a native macOS app and it is a major differentiator vs. Electron-based competitors.

- [ ] **Session Pinboard / Favorites** -- Add a "pinned" section at the top of SessionListView for starred sessions. Quick-pin via right-click or Cmd+D. Pinned sessions persist across date filters. Simple feature that dramatically improves navigation for users with hundreds of sessions.

### Export and Integration

- [ ] **Markdown Export with YAML Frontmatter** -- Export sessions as clean Markdown files with YAML frontmatter (title, date, duration, tags) ready for Obsidian/Logseq vaults. Include transcript as timestamped text, summaries as structured sections, and action items as task lists. Offer "Export to folder" with configurable output directory (per-vault targeting). Obsidian users are the most vocal PKM community and they will champion an app that integrates cleanly with their workflow.

- [ ] **Auto-Export Pipeline** -- Configurable auto-export that triggers after each recording completes: write Markdown to a chosen folder, copy action items to clipboard, or send a webhook/URL scheme. Pairs with the Markdown export above to create a zero-friction Obsidian/Notion workflow. Shadow and Lindy built their value prop on "your meeting notes just appear where you need them."

- [ ] **Share as Rich Summary Card** -- Generate a shareable HTML or image card from a session summary (title, key points, action items, duration) that looks great when pasted into Slack, email, or docs. Use NSAttributedString rendering or SwiftUI-to-image capture. More polished than raw text paste and much more likely to be shared with teammates.

### Local-First Differentiators

- [ ] **Offline-First LLM with Bundled Model Profiles** -- Ship curated model profiles for popular local LLM setups (Ollama + llama3, LM Studio + qwen3, MLX models). Include one-click "Test Connection" in settings and a setup wizard for first-time users. Show estimated quality/speed for each model on the user's hardware. The biggest barrier to local LLM usage is configuration friction -- reducing it to one click is a competitive moat that cloud-only services cannot match.

- [ ] **Speaker Diarization Labels** -- The `TranscriptSegment.speakerLabel` field already exists but is unused. Implement basic speaker change detection using audio energy patterns and silence gaps, then let users name speakers post-recording ("Speaker 1" -> "Alice"). Display speaker labels as colored badges in the transcript. Optionally use the LLM to infer speaker names from context ("Based on the transcript, Speaker 1 appears to be the project manager..."). This is consistently the #1 requested feature in meeting transcription apps.

- [ ] **Confidential Mode with Session Encryption** -- Offer per-session encryption using a user-provided password (CryptoKit AES-GCM). Encrypted sessions show a lock icon and require the password to view. Audio files, transcripts, and summaries all encrypted at rest. No cloud service can offer this level of data sovereignty. Positions the app for sensitive use cases: legal, medical, HR, journalism, therapy notes.

### Accessibility and Inclusivity

- [ ] **Real-Time Translation Overlay** -- During live recording, offer an optional secondary panel showing the transcript translated into a user-chosen language via the LLM. Useful for multilingual meetings or language learners. Store translations alongside the original transcript. No competitor offers local real-time translation -- this is a genuine differentiator.

- [ ] **VoiceOver and Accessibility Audit** -- Conduct a full VoiceOver audit of every view. Add proper `accessibilityLabel`, `accessibilityHint`, and `accessibilityValue` to all interactive elements. Ensure the waveform and audio level meter have text alternatives. Support Dynamic Type scaling. Test with Switch Control. Most transcription apps have poor accessibility -- being best-in-class here wins institutional buyers (universities, government, healthcare).
