# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.1] - 2026-04-01 — App Store Review Fixes

### Added

- First-time onboarding: 4-page Welcome Guide (intro, recording tips, features, quick LLM setup) with privacy notice that falls back to Apple Intelligence on decline; Help menu entries for Welcome Guide and Data Usage Information
  Files: WelcomeView.swift, PrivacyDisclosureView.swift, ContentView.swift, notetakerApp.swift
- VoiceOver accessibility: labels, hints, and values across PlaybackControlView, TranscriptView, ActionItemListView, SessionDetailView, and SettingsTab
  Files: PlaybackControlView.swift, TranscriptView.swift, ActionItemListView.swift, SessionDetailView.swift, SettingsTab.swift
- Playback auto-scroll & highlight: auto-scroll and highlight current transcript segment / summary chunk during audio playback; dim non-active items (opacity 0.35); scroll to position on tab switch while playing; only active during playback state
  Files: SessionDetailView.swift, TranscriptView.swift
- `listModels()` API on all LLM engines (Ollama/OpenAI/Anthropic) for remote model listing
  Files: LLMEngine.swift, OllamaEngine.swift, OpenAIEngine.swift, AnthropicEngine.swift
- Per-profile connection test dot indicator (persisted via `lastTestedAt`/`lastTestPassed`); token usage stats (`totalInputTokens`/`totalOutputTokens`/`totalRequests`) tracked per profile via `LLMProfileStore.recordUsageForConfig()`
  Files: LLMModelProfile.swift, SummarizerService.swift, ChatService.swift, ModelsSettingsTab.swift
- VAD test in Recording settings: lightweight mic capture with real-time audio level bar, threshold marker, and speech/silence indicator; auto-restarts on config change
  Files: SettingsTab.swift
- `CustomProviderDisclaimerView` — first-time compliance disclaimer for custom API endpoints in China region
  Files: CustomProviderDisclaimerView.swift

### Changed

- App name unified to "TranscribeNote": PRODUCT_NAME = TranscribeNote with PRODUCT_MODULE_NAME = notetaker; updated CFBundleName, CFBundleDisplayName, TEST_HOST, usage descriptions; scheme BuildableName to TranscribeNote.app; calendar/reminders usage keys upgraded to FullAccess variants (Guideline 2.3.8)
  Files: project.pbxproj, notetaker.xcscheme
- China App Store compliance (Guideline 5): disabled Apple Intelligence & foreign providers (OpenAI/Anthropic) in CN storefront via async `SKStorefront` detection with locale fallback; refactored Models settings UI from Form/.columns to Grid layout
  Files: LLMProvider.swift, LLMEngineFactory.swift, ModelsSettingsTab.swift, PrivacyDisclosureView.swift, notetakerApp.swift, LLMProviderTests.swift, LLMEngineFactoryTests.swift, LLMConfigCoverageTests.swift
- Session detail UI: replaced stacked overall summary + transcript with segmented subtab picker (Summary/Transcript); removed hover copy button from TranscriptSegmentRow (reopened #35); enabled cross-row text selection in TranscriptView
  Files: SessionDetailView.swift, TranscriptSegmentRow.swift, SummaryCardView.swift, TranscriptView.swift
- Models management: "Manage Models" button inline with available/total count; aligned sidebar/detail bottom bar height; enlarged profile list row font and spacing; removed "None" from role profile pickers
  Files: ModelsSettingsTab.swift, SettingsTab.swift, notetakerApp.swift

### Fixed

- Session detail first-load lag: removed duplicate loadAudio call; async multi-clip duration via AVURLAsset; pre-computed summary/actionItem/hasAudioFiles state; cached `SummaryBlock.structuredSummary` with `@Transient`; converted `TranscriptView.displayItems` to `@State`
  Files: SessionDetailView.swift, AudioPlaybackService.swift, SummaryBlock.swift, TranscriptView.swift
- Sidebar snap-back during recording drain: guard `handleCompletionIfNeeded()` with `selectedSessionID == nil` check; reduced minimum window size to 400×300
  Files: ContentView.swift
- Key points text wrapping overlap in SummaryCardView
  Files: SummaryCardView.swift

## [1.0.0] - 2026-03-25

### Added

- Apple Foundation Models as zero-config default LLM engine (#17): `FoundationModelsEngine` with safe availability check, `.foundationModels` provider as default, async `createWithFallback()`, BackgroundSummaryService auto-fallback, Settings UI with "Apple Intelligence (On-Device)" option; created #44 for future @Generable structured output
  Files: FoundationModelsEngine.swift, LLMProvider.swift, LLMConfig.swift, LLMEngineFactory.swift, BackgroundSummaryService.swift, SettingsView.swift, FoundationModelsEngineTests.swift, LLMEngineFactoryFallbackTests.swift
- Two-tier test plan strategy: UnitTests (pure-logic suites, <0.2s) for local dev and FullTests (all suites + UI tests) for CI; shared Xcode scheme with test plan associations
  Files: UnitTests.xctestplan, FullTests.xctestplan, notetaker.xcscheme
- Reusable settings components library (SettingsComponents.swift): SettingsDescription, SettingsSlider, SettingsIntSlider, StatusIndicator, .settingsFooter(), SettingsInfoLabel; restored 4-tab settings layout
  Files: SettingsComponents.swift, ModelsSettingsTab.swift, SettingsTab.swift, AboutTab.swift, SettingsView.swift
- One-click copy summary as Markdown (#38): hover-to-reveal copy button on SummaryCardView with checkmark animation; SummaryMarkdownFormatter; 6 unit tests
  Files: SummaryMarkdownFormatter.swift, SummaryCardView.swift, SummaryMarkdownFormatterTests.swift
- 34 detailed GitHub feature issues (#10–#43) from enhancement plan with priority labels, implementation plans, and acceptance criteria
- 213 app improvement proposals across 12 rounds; renamed PLAN.md to PROPOSAL.md
  Files: PROPOSAL.md

### Changed

- UserDefaults DI (`defaults: UserDefaults = .standard`) into 5 production files for test isolation; moved 6 suites into UnitTests plan (330 tests in 28 suites)
  Files: LLMConfig.swift, LLMModelProfile.swift, SummarizerConfig.swift, VADConfig.swift, KeychainMigration.swift
- CI: test and claude-review run sequentially; PR approval uses PAT instead of GITHUB_TOKEN
  Files: .github/workflows/auto-merge.yml

### Fixed

- 315 new tests across 10 files; `.serialized` on 19 test suites to fix parallel UserDefaults/Keychain contamination; 737/737 tests pass
- Test coverage improved from 21% to 23% with 13 new test files; 15+ source files at 100% coverage

### Security

- Resolved VAD data race (CRITICAL), multi-clip audio deletion, prompt injection mitigation, resultTask timeout cancellation, NoopASREngine thread safety, Keychain empty-key guard, migration failure cleanup, URL scheme validation, HTTP error truncation, smart retry logic, API key leak warning, sensitive data logging cleanup
  Files: AudioCaptureService.swift, SessionListView.swift, PromptBuilder.swift, SpeechAnalyzerEngine.swift, NoopASREngine.swift, LLMConfig.swift, LLMModelProfile.swift, KeychainMigration.swift, LLMEngine.swift, OpenAIEngine.swift, OllamaEngine.swift, AnthropicEngine.swift, SummarizerService.swift, BackgroundSummaryService.swift
