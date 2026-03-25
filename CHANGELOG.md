# Changelog

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

## [2026-03-25 01:05]

- Added GitHub Actions CI workflow for auto review & merge (#46): uses anthropics/claude-code-action@v1 with CLAUDE_CODE_OAUTH_TOKEN to review PR diffs against CLAUDE.md conventions; auto-merges when tests pass + Claude approves; pre-cleanup cancels redundant runs and removes stale review comments; post-cleanup deletes old workflow runs (>30d) and stale merged branches
  Files: .github/workflows/auto-merge.yml

## [2026-03-25 01:10]

- Created release branch with GitHub ruleset protection (PR required, 1 approving review, signed commits, no force push, no deletion, required status checks, CodeQL code scanning); added CI workflow (build + conditional test by macOS version) and CodeQL workflow for main/release branches; auto-creates/comments GitHub issue when tests are skipped due to macOS < 26; tagged issues #10–#44 with `feature` label
  Files: .github/workflows/ci.yml, .github/workflows/codeql.yml, .github/workflows/auto-merge.yml

## [2026-03-25 01:28]

- Extracted reusable settings components library (SettingsComponents.swift): SettingsDescription, SettingsSlider, SettingsIntSlider, StatusIndicator, .settingsFooter(), SettingsInfoLabel; restored original 4-tab settings layout (Models/LLM/Summarization/Recording) from monolithic SettingsView.swift into separate tab files; added "Report a Bug" link to About tab
  Files: SettingsComponents.swift, ModelsSettingsTab.swift, SettingsTab.swift, AboutTab.swift, SettingsView.swift, LLMProvider.swift
