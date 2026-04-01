# Changelog

## [2026-04-01] App Store Review Fixes (v1.0.1)

- **App name unified to "TranscribeNote"**: Set PRODUCT_NAME = TranscribeNote with PRODUCT_MODULE_NAME = notetaker to preserve Swift module; updated CFBundleName, CFBundleDisplayName, TEST_HOST, and all usage description strings (microphone, speech, calendar, reminders) to use "TranscribeNote" consistently (Guideline 2.3.8)
  Files: project.pbxproj

- **China App Store compliance (Guideline 5)**: Added 4 new LLM providers with proper 备案 filing — DeepSeek (浙ICP备2023025841号), Moonshot AI (网信算备110108896786101240015号), Zhipu AI (Beijing-ChatGLM-20230821), MiniMax (沪ICP备2023003282号); each with defaultBaseURL, defaultModel, filingURL; OpenAI/Anthropic hidden in CN region via `LLMProvider.isChineseStorefront` locale detection; "Custom (OpenAI-compatible)" remains available everywhere; removed hardcoded "OpenAI, Anthropic" brand references from PrivacyDisclosureView; added `requiresAPIKey`, `isAvailableInChina`, `availableProviders` properties; all new providers route through OpenAIEngine (OpenAI-compatible APIs)
  Files: LLMProvider.swift, LLMEngineFactory.swift, ModelsSettingsTab.swift, PrivacyDisclosureView.swift, LLMProviderTests.swift, LLMEngineFactoryTests.swift, LLMConfigCoverageTests.swift

## [2026-03-24]

- Security review and fixes: resolved VAD data race (CRITICAL), multi-clip audio deletion, prompt injection mitigation, resultTask timeout cancellation, NoopASREngine thread safety, Keychain empty-key guard, migration failure cleanup, URL scheme validation, HTTP error truncation, smart retry logic, API key leak warning, and sensitive data logging cleanup
  Files: AudioCaptureService.swift, SessionListView.swift, PromptBuilder.swift, SpeechAnalyzerEngine.swift, NoopASREngine.swift, LLMConfig.swift, LLMModelProfile.swift, KeychainMigration.swift, LLMEngine.swift, OpenAIEngine.swift, OllamaEngine.swift, AnthropicEngine.swift, SummarizerService.swift, BackgroundSummaryService.swift, SettingsView.swift, CrashLogService.swift, PromptBuilderTests.swift

- Improved test coverage from 21% to 23% by adding 13 new test files covering LLMConfig, LLMModelProfile, LLMProvider, LLMEngineFactory, LLMHTTPHelpers, NoopASR/LLMEngine, AudioExportError, LLMEngineError, TokenUsage, KeychainMigration, RecordingViewModel, SummarizerConfig, SummaryBlock, RecordingSession, ScheduledRecording, RepeatRule, CalendarService, and CrashLogService; brought 15+ source files to 100% coverage
  Files: LLMConfigTests.swift, LLMModelProfileTests.swift, LLMProviderTests.swift, LLMEngineFactoryTests.swift, LLMHTTPHelpersTests.swift, NoopEngineTests.swift, KeychainMigrationExtendedTests.swift, RecordingViewModelExtendedTests.swift, SummarizerConfigExtendedTests.swift, RecordingSessionExtendedTests.swift, ScheduledRecordingExtendedTests.swift, CalendarServiceExtendedTests.swift, CrashLogServiceExtendedTests.swift

- Added 315 new tests across 10 files (5,188 lines) via parallel agent swarm covering AudioExporter, BackgroundSummaryService, RecordingViewModel state machine/dedup/forceQuit, AudioCaptureService+SimpleVAD edge cases, SummarizerService full API, PromptBuilder full API, CrashLogService file lifecycle, LLMConfig/Provider/Profile/Store, TranscriptExporter formatting+clipboard, and SchedulerViewModel scheduling/calendar/repeat; added .serialized to 19 test suites to fix parallel UserDefaults/Keychain contamination; 737/737 tests pass (2 cross-suite race condition tests documented and disabled)
  Files: AudioExporterTests.swift, BackgroundSummaryServiceTests.swift, RecordingViewModelCoverageTests.swift, AudioCaptureServiceExtendedTests.swift, SummarizerServiceExtendedTests.swift, PromptBuilderExtendedTests.swift, CrashLogServiceCoverageTests.swift, LLMConfigCoverageTests.swift, TranscriptExporterExtendedTests.swift, SchedulerViewModelExtendedTests.swift, KeychainServiceTests.swift, KeychainMigrationTests.swift, LLMConfigTests.swift, LLMProviderTests.swift, LLMEngineFactoryTests.swift, LLMHTTPHelpersTests.swift, LLMModelProfileTests.swift, NoopEngineTests.swift, TranscriptExporterTests.swift, SchedulerViewModelTests.swift, VADConfigTests.swift, SummarizerConfigExtendedTests.swift, CalendarServiceTests.swift, CalendarServiceExtendedTests.swift, ScheduledRecordingTests.swift, ScheduledRecordingExtendedTests.swift, KeychainMigrationExtendedTests.swift

## [2026-03-24 22:46]

- Evaluated PROPOSAL.md (106 improvement points across 7 rounds) and generated Chinese translation plan_zh.md; diagnosed and resolved ralph-loop plugin infinite Stop hook loop
  Files: plan_zh.md, .claude/ralph-loop.local.md

## [2026-03-24 23:19]

- Brainstormed 213 app improvement proposals across 12 rounds (AI intelligence, UX polish, frontend craft, new features, interaction & intelligence, fresh angles, deep integration, emotional craft, content alchemy, final polish, app identity); renamed PLAN.md to PROPOSAL.md to better reflect its purpose
  Files: PROPOSAL.md

## [2026-03-24 23:47]

- Created 34 detailed GitHub feature issues from plan_zh.md enhancement plan with priority labels, competitive analysis (WebSearch), implementation plans, file impact lists, and acceptance criteria; covers AI features, UX polish, export/integration, local-first, accessibility, platform-native (macOS 26), and automation
  Files: (GitHub issues #10-#43, no local file changes)

## [2026-03-25 00:25]

- Added two-tier test plan strategy: UnitTests (22 pure-logic suites, 257 tests, <0.2s) for local dev and FullTests (all suites + UI tests) for CI on PR to main; created shared Xcode scheme with test plan associations; UnitTests set as default for Cmd+U
  Files: UnitTests.xctestplan, FullTests.xctestplan, notetaker.xcodeproj/xcshareddata/xcschemes/notetaker.xcscheme

## [2026-03-25 00:30]

- Integrated Apple Foundation Models as zero-config default LLM engine (#17): added FoundationModelsEngine with safe availability check (never crashes if Apple Intelligence not enabled), .foundationModels provider as new default, async createWithFallback() in LLMEngineFactory, BackgroundSummaryService auto-fallback, and Settings UI with "Apple Intelligence (On-Device)" option hiding irrelevant fields; created #44 for future @Generable structured output
  Files: FoundationModelsEngine.swift, LLMProvider.swift, LLMConfig.swift, LLMEngineFactory.swift, BackgroundSummaryService.swift, SettingsView.swift, FoundationModelsEngineTests.swift, LLMEngineFactoryFallbackTests.swift, LLMEngineFactoryTests.swift, LLMConfigTests.swift, LLMProviderTests.swift, LLMConfigCoverageTests.swift, LLMModelProfileTests.swift

## [2026-03-25 00:44]

- Injected UserDefaults DI (`defaults: UserDefaults = .standard`) into 5 production files to enable test isolation via `UserDefaults(suiteName:)`; eliminated cross-suite UserDefaults conflicts; moved 6 newly-parallel suites (+73 tests) into UnitTests plan (now 330 tests in 28 suites, 0.22s); fixed `saveAndLoadProfiles` crash with `try #require`; re-enabled 2 previously disabled tests
  Files: LLMConfig.swift, LLMModelProfile.swift, SummarizerConfig.swift, VADConfig.swift, KeychainMigration.swift, LLMConfigTests.swift, LLMConfigCoverageTests.swift, LLMModelProfileTests.swift, LLMProviderTests.swift, SummarizerConfigExtendedTests.swift, VADConfigTests.swift, KeychainMigrationTests.swift, KeychainMigrationExtendedTests.swift, UnitTests.xctestplan

## [2026-03-25 01:28]

- Extracted reusable settings components library (SettingsComponents.swift): SettingsDescription, SettingsSlider, SettingsIntSlider, StatusIndicator, .settingsFooter(), SettingsInfoLabel; restored original 4-tab settings layout (Models/LLM/Summarization/Recording) from monolithic SettingsView.swift into separate tab files; added "Report a Bug" link to About tab
  Files: SettingsComponents.swift, ModelsSettingsTab.swift, SettingsTab.swift, AboutTab.swift, SettingsView.swift, LLMProvider.swift

- CI: made test and claude-review run sequentially (pre-cleanup → test → claude-review → auto-merge → post-cleanup); fixed PR approval to use PAT instead of GITHUB_TOKEN
  Files: .github/workflows/auto-merge.yml

## [2026-03-25 02:34]

- feat: one-click copy summary as Markdown (#38) — hover-to-reveal copy button on SummaryCardView with checkmark animation feedback; SummaryMarkdownFormatter for testable Markdown formatting; 6 unit tests
  Files: SummaryMarkdownFormatter.swift, SummaryCardView.swift, SummaryMarkdownFormatterTests.swift

## [2026-04-01 13:25]

- fix: disable Apple Intelligence in China App Store for legal compliance; use StoreKit SKStorefront for storefront detection; add first-time compliance disclaimer for custom API endpoint in China region
  Files: LLMProvider.swift, notetakerApp.swift, CustomProviderDisclaimerView.swift, ModelsSettingsTab.swift, LLMProviderTests.swift

## [2026-04-01 13:30]

- feat: add VAD test button in Recording settings — lightweight mic capture with real-time audio level bar, threshold marker, and speech/silence indicator; auto-restarts on config change, cleans up on disappear
  Files: SettingsTab.swift

## [2026-04-01 14:30]

- perf: fix session detail first-load lag — removed duplicate loadAudio call in fetchSession; async-ified multi-clip duration computation via AVURLAsset; pre-computed summary/actionItem/hasAudioFiles state to eliminate repeated linear scans and FileManager calls in body; cached SummaryBlock.structuredSummary with @Transient to avoid repeated JSON decoding; converted TranscriptView.displayItems from computed property to @State
  Files: SessionDetailView.swift, AudioPlaybackService.swift, SummaryBlock.swift, TranscriptView.swift

## [2026-04-01 14:30]

- fix: China App Store compliance — disable Apple Intelligence & foreign providers in CN storefront (StoreKit detection), add custom endpoint compliance disclaimer, refactor Models settings UI from Form/.columns to Grid layout for consistent left-aligned fields across all providers
  Files: LLMProvider.swift, notetakerApp.swift, CustomProviderDisclaimerView.swift, ModelsSettingsTab.swift, LLMProviderTests.swift

## [2026-04-01 14:38]

- refactor: replace stacked overall summary + transcript with segmented subtab picker (Summary/Transcript); remove hover copy button from TranscriptSegmentRow (reopened #35); fix key points text wrapping overlap in SummaryCardView; enable cross-row text selection in TranscriptView
  Files: SessionDetailView.swift, TranscriptSegmentRow.swift, SummaryCardView.swift, TranscriptView.swift

## [2026-04-01 14:54]

- fix: guard handleCompletionIfNeeded() with selectedSessionID == nil check to prevent sidebar snap-back when user navigates during recording drain
  Files: ContentView.swift

## [2026-04-01 15:40]

- feat: add first-time user onboarding with 4-page Welcome Guide (intro, recording, features, quick LLM setup), privacy notice with Decline option that falls back to Apple Intelligence, and Help menu entries for Welcome Guide and Data Usage Information
  Files: WelcomeView.swift, PrivacyDisclosureView.swift, ContentView.swift, notetakerApp.swift

## [2026-04-01 15:55]

- feat: add VoiceOver accessibility labels/hints/values across key views, move "Manage Models" button inline in LLM settings row with available/total count, add per-profile connection test dot indicator (persisted) and token usage stats in Models window
  Files: PlaybackControlView.swift, TranscriptView.swift, ActionItemListView.swift, SessionDetailView.swift, SettingsTab.swift, LLMModelProfile.swift, SummarizerService.swift, ChatService.swift, ModelsSettingsTab.swift

## [2026-04-01 15:58]

- fix: align Models sidebar/detail bottom bar height, enlarge profile list row font and spacing, increase Models window height to 600, remove "None" option from role profile pickers and default to first profile
  Files: ModelsSettingsTab.swift, SettingsTab.swift, notetakerApp.swift

## [2026-04-01 15:58]

- feat: auto-scroll and highlight current transcript segment / summary chunk during audio playback; dim non-active items (opacity 0.35); scroll to position on tab switch while playing; only active during playback state
  Files: SessionDetailView.swift, TranscriptView.swift
