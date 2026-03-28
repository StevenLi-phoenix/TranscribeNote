# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A macOS note-taking/transcription app with live ASR, audio recording/playback, LLM-powered summarization, and session history.

- **Platform:** macOS 26.2+
- **Language:** Swift 5
- **UI Framework:** SwiftUI
- **Xcode scheme:** `notetaker`

## Build & Test Commands

```bash
# Build
xcodebuild -scheme notetaker -configuration Debug build

# Run fast unit tests only (pure logic, no shared state — default for local dev)
xcodebuild -scheme notetaker -testPlan UnitTests -configuration Debug test

# Run full test suite (all unit + UI tests — for CI / PR to main)
xcodebuild -scheme notetaker -testPlan FullTests -configuration Debug test

# Run a specific test suite (e.g., RingBufferTests)
xcodebuild -scheme notetaker -configuration Debug -only-testing:notetakerTests/RingBufferTests test

# Run UI tests
xcodebuild -scheme notetaker -configuration Debug -only-testing:notetakerUITests test
```

## Key Patterns & Gotchas

### Build & Project
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types MainActor by default; use `nonisolated` for audio/ASR/LLM classes
- `PBXFileSystemSynchronizedRootGroup` — no pbxproj edits needed for new source files
- `import os` provides both `Logger` AND `OSAllocatedUnfairLock` — don't remove from files using either
- Entitlements: sandbox + audio-input + `files.user-selected.read-write` + `network.client` (LLM API calls) + `personal-information.calendars` (calendar import)

### SwiftData & SwiftUI
- SwiftData persistence with `@Model` classes (`RecordingSession`, `TranscriptSegment`, `SummaryBlock`)
- MenuBarExtra does NOT inherit `.modelContainer` from WindowGroup — must share `ModelContainer` explicitly
- Never put SwiftData `fetch()` in a computed property used by SwiftUI body — use `@State` + `onAppear`/`onChange`
- Slider seek: use `onEditingChanged` to defer `seek(to:)` — direct binding causes audio glitching
- Extract frequently-updated `@Observable` properties into separate class (e.g., `ElapsedTimeClock` defined at top of `RecordingViewModel.swift`) to prevent invalidating unrelated views on timer tick
- Timer callbacks on `@Observable` classes already run on main thread — do NOT wrap in `Task { @MainActor }`
- Even with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, always add explicit `@MainActor` to `Task` closures that access UI state after an `await` suspension point — implicit isolation is fragile across refactors
- Use `SettingsLink()` in MenuBarExtra to open Settings scene — `NSApp.sendAction(Selector(("showSettingsWindow:")))` causes ViewBridge/RemoteViewService errors
- SwiftUI `List(selection: $setBinding)` with `Set<UUID>` provides Cmd+A (select all) for free; use `.onDeleteCommand` for Delete key; `.contextMenu(forSelectionType:)` for multi-select context menus
- Cancel long-running `Task`s on view disappear: store in `@State`, cancel in `.onDisappear` and `.onChange(of: sessionID)` — prevents detached tasks modifying SwiftData after navigation
- Re-fetch SwiftData `@Model` objects after `await` in async Tasks — captured references may be stale; re-fetch by ID with `#Predicate`
- Reset transient view state (`isGeneratingSummary`, `hasAutoTriggered`, errors) in `onChange(of: sessionID)` — prevents stale flags blocking behavior on navigation
- **SwiftData property defaults for migration**: New non-optional stored properties on `@Model` classes MUST have inline default values on the property declaration (e.g., `var isOverall: Bool = false`), NOT just in `init()` — SwiftData uses the property-level default to fill existing rows during lightweight migration; `init` defaults are ignored
- **Schema versioning**: `NotetakerMigrationPlan` in `Models/Schemas/` — ModelContainer initialized with `migrationPlan: NotetakerMigrationPlan.self`; all 6 versions use lightweight migrations:
  - **V1**: Initial schema (RecordingSession, TranscriptSegment, SummaryBlock)
  - **V2**: Adds `editedContent: String? = nil` to SummaryBlock; `displayContent` computed property returns editedContent ?? content
  - **V3**: Adds `ScheduledRecording` model for timed recording scheduling
  - **V4**: Adds `audioFilePaths: [String] = []` to RecordingSession for multi-clip pause/resume
  - **V5**: Adds `isPartial: Bool = false` to RecordingSession for force-quit detection
  - **V6**: Adds `calendarEventIdentifier: String? = nil` to ScheduledRecording, `scheduledRecordingID: UUID? = nil` to RecordingSession
- **Design System tokens**: `DS` enum in `DesignSystem.swift` centralizes spacing (4pt grid), typography, colors, radii, layout constants; `ViewModifiers.swift` provides `.cardStyle()` and `.badgeStyle()`; `ControlBarMetrics` aliases DS values
- **Session search**: `SessionListView` uses `.searchable()` filtering by title, segment text, summary content; debounced 300ms to prevent SwiftData fault storms; `DateFilter` enum for Today/This Week/This Month quick filters

### Privacy & App Store
- **Privacy disclosure**: `PrivacyDisclosureView` shown as sheet on first `LLMSettingsTab` `onAppear` via `@AppStorage("hasShownPrivacyDisclosure")`; reset via Help > Data Usage Information menu or `defaults delete <bundle-id> hasShownPrivacyDisclosure`
- **Privacy policy**: `docs/PRIVACY_POLICY.md` — host at public URL for App Store Connect
- **App Store checklist**: `docs/APP_STORE_PRIVACY_CHECKLIST.md` — covers Privacy Nutrition Labels, entitlements justification, review notes template

### Audio & ASR
- Audio tap singleton: only ONE tap per `AVAudioEngine` bus; `AudioCaptureService` owns the tap
- SpeechAnalyzerEngine uses `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26+) — no time limit, native volatile/final results; MUST call `analyzer.finalizeAndFinishThroughEndOfInput()` when stopping — without it `transcriber.results` never terminates
- `ASREngine` protocol: `stopRecognition()` is `async` (enables result drain); `onResult` is `@Sendable async` closure; `appendAudioBuffer(_:)` — never downcast to concrete engine type
- `AudioCaptureService` records M4A/AAC by default (128kbps) with automatic WAV fallback — old `.wav` files still play fine (`AVAudioPlayer` is format-agnostic)
- `AudioCaptureService.onAudioLevel` callback in `State` struct — RMS calculated on writeQueue, log-scaled to 0..1 (-50dB→0, 0dB→1); throttle with `OSAllocatedUnfairLock<Float>` on audio thread before dispatching to MainActor
- `AudioLevelMeter` (`@Observable` in `RecordingViewModel.swift`) — same pattern as `ElapsedTimeClock` to isolate high-frequency audio level updates from invalidating unrelated views
- **VAD (Voice Activity Detection)**: `SimpleVAD` (`nonisolated final class: @unchecked Sendable`) gates ASR buffer forwarding in `AudioCaptureService`; uses `OSAllocatedUnfairLock` with buffer-count-based thresholds (not timestamps) for zero syscall overhead on audio thread; returns `.forward`/`.suppress`/`.silenceTimeout`; `VADConfig` stored as JSON in `@AppStorage("vadConfigJSON")`; audio file write and level callback always fire regardless of VAD state; `onSilenceTimeout` callback in `AudioCaptureService.State` triggers auto-stop via `RecordingViewModel`
- **VAD logger gotcha**: `OSAllocatedUnfairLock.withLock` closure captures `inout state` — `Logger` string interpolation of state fields is an escaping autoclosure that captures inout, causing compile error; extract values before logging outside the lock

### LLM & Summarization
- `LLMEngine` protocol: `generate(messages:config:)`, `isAvailable(config:)`, `supportsStructuredOutput`, `generateStructured(messages:schema:config:)`, `supportsToolCalling`, `generateWithTools(messages:tools:config:)` — `nonisolated`, `AnyObject`, `Sendable`, injectable `URLSession` for testing; protocol extension provides defaults returning `false` / throwing `.notSupported` for structured output and tool calling
- **Structured Output**: `JSONSchema` (name, description, schemaData as raw JSON `Data`, strict) + `StructuredOutput` (data, usage, `decode<T>()`) — enables JSON schema-constrained generation; OpenAI uses `response_format`, Anthropic uses `output_config.format`, Ollama uses `format` parameter; FoundationModels does not support runtime schemas (`@Generable` is compile-time only)
- **Tool Calling**: `LLMTool` (name, description, parameters as `JSONSchema`, async handler) + `LLMToolCall` (id, name, arguments as `Data`) + `LLMToolResponse` (`.text`/`.toolCalls`) — enables function calling for agent scenarios; `executeToolLoop()` top-level function automates call→execute→feed-back cycles with configurable max iterations; OpenAI/Anthropic/Ollama engines implement tool calling; FoundationModels/Noop get default `.notSupported`; Anthropic sends tool results as `tool_result` content blocks in user messages; Ollama uses `/api/chat` endpoint with synthetic tool call IDs (`ollama-0`, `ollama-1`, ...)
- `LLMMessage` struct: `role` (`.system`/`.user`/`.assistant`/`.tool`), `content`, `cacheHint`, `usage: TokenUsage?`, `toolCalls: [LLMToolCall]?` (assistant messages requesting tool invocations), `toolCallId: String?` (tool result messages)
- Five implementations: `FoundationModelsEngine` (Apple Intelligence on-device), `OllamaEngine`, `OpenAIEngine`, `AnthropicEngine`, `NoopLLMEngine` — created via `LLMEngineFactory.create(from:session:)`; `.custom` provider maps to `OpenAIEngine` (OpenAI-compatible API for LM Studio etc.)
- **Foundation Models fallback**: `LLMEngineFactory.createWithFallback()` tries primary engine, falls back to `FoundationModelsEngine` if primary unavailable and Apple Intelligence is enabled; `FoundationModelsEngine.isModelAvailable` checks `SystemLanguageModel.default.availability`
- `SummarizerService` orchestrates: guard minTranscriptLength → build prompt via `PromptBuilder` → call LLM with retry (3 attempts, 10s/30s/60s backoff, only retries network/HTTP errors)
- `SummarizerService.summarizeInChunks()` yields `ChunkProgress` per time window; `summarizeOverall()` synthesizes chunk summaries into a single overall summary
- `SummarizerService.splitIntoChunks()` uses zero-based windows: window 0 = `[0, interval)`, window 1 = `[interval, 2*interval)` — segments assigned by `Int(startTime / intervalSeconds)`; `splitIntoChunksWithWindowIndices()` returns window indices for boundary calculations
- `PromptBuilder` uses shared `styleInstructions(style:task:)` helper for DRY style formatting; `constraintBlock(config:)` enforces no-preamble output and language compliance; `sanitizeLanguage()` strips newlines and limits to 50 chars to prevent prompt injection; `sanitizeInstructions()` limits to 500 chars for guided regeneration
- `AnthropicEngine` guards empty `apiKey` with `.notConfigured` error (unlike OpenAI which skips the header for local/keyless setups)
- `LLMHTTPHelpers` enum in `LLMEngine.swift` consolidates shared HTTP methods (`performRequest`, `validateHTTPResponse`, `decodeResponse`) — don't duplicate in individual engines
- **LLM Profile System**: `LLMModelProfile` (named config) + `LLMRole` enum (`.live`, `.overall`, `.title`, `.chat`) + `LLMProfileStore` (CRUD, role assignment, config resolution); profiles stored as JSON array in UserDefaults, API keys in Keychain per-profile (`notetaker.profile.<uuid>.apiKey`); roles can "inherit live" to reuse the live profile; `resolveConfig(for:)` resolves assigned profile → first profile → legacy fallback; auto-migrates from legacy per-role `@AppStorage` keys on first launch
- **`LLMConfig` API key security**: `apiKey` stored in macOS Keychain via `KeychainService`, NOT in UserDefaults JSON; custom `CodingKeys` excludes `apiKey` from encoding/decoding; one-time migration via `KeychainMigration.migrateIfNeeded()` at app init
- **`OverallSummaryMode`**: `.rawText` (full transcript), `.chunkSummaries` (synthesize existing chunks), `.auto` (chunks if available, else raw) — stored in `SummarizerConfig`
- Default config: `.custom` provider, `qwen3-14b-mlx` model, `http://localhost:1234/v1` (LM Studio)
- `SummaryBlock` stores `style` as `String` raw value (SwiftData can't store custom enums directly); use `summaryStyle` computed property; `isOverall: Bool` distinguishes overall summaries from chunk summaries; `editedContent: String?` for user edits — use `displayContent` computed property which returns editedContent ?? content
- Silent summaries: No spinners during summary generation; summaries fade in with `.transition(.opacity)` + `.animation(.easeIn)` on count; errors auto-dismiss after 5s via `.task(id:)`
- Guided regeneration: `SummarizerService.summarizeWithInstructions()` passes `additionalInstructions` through `PromptBuilder`; `retryableGenerate()` extracted as shared retry logic
- **`BackgroundSummaryService`**: `@MainActor` singleton that dispatches overall summary + title generation after recording ends, independent of view lifecycle; uses its own `ModelContext` so summaries persist even if user navigates away; `activeTasks: [UUID: Task]` prevents double-dispatch; `awaitAll()` for graceful quit; generates title via separate `LLMRole.title` config after summary completes
- **`ChatService`**: `nonisolated final class: @unchecked Sendable` for conversational transcript Q&A; manages conversation history with `NSLock`; builds system prompt with transcript context (`cacheHint: true`); `formatTranscript()` truncates at 60K chars (front 40% + back 40%); trims conversation to last 10 pairs; no retry logic (fail fast for interactive chat); uses `LLMRole.chat` config
- **`ChatMessage`**: `nonisolated struct: Identifiable, Sendable` — ephemeral in-memory model (not SwiftData); `role` reuses `LLMMessage.Role`; `isError` flag for inline error display
- **Chat Panel**: `ChatView` + `VerticalResizeHandle` in `SessionDetailView` via `HStack`; toggled from toolbar (`bubble.left.and.bubble.right`); width persisted via `@AppStorage("chatPanelWidth")`; preset question buttons when empty; `FlowLayout` for button wrapping; resets on session change
- **`AudioExporter`**: Merges multiple audio clips into single M4A via `AVMutableComposition` + `AVAssetExportSession`; single-clip case copies directly; used when `RecordingSession.audioFilePaths` has multiple entries from pause/resume
- **Multi-clip recording**: Pause/resume creates separate audio clips stored in `RecordingSession.audioFilePaths: [String]`; `AudioExporter.mergeAndExport()` combines them on session completion; `audioFilePath` (singular) retained for backward compatibility
- **`SummaryMarkdownFormatter`**: Formats `SummaryBlock` content as Markdown with time-range or "Overall Summary" heading; used by copy-summary feature
- **`AudioConfig`**: `nonisolated Sendable` struct with `sampleRate`, `channels`, `bufferDurationSeconds`; `AudioConfig.default` = 16kHz mono, 30s buffer

### Thread Safety
- `SpeechAnalyzerEngine` uses serial `DispatchQueue` for thread safety — all mutable state accessed through `queue`; `stopRecognition()` is async with 4-phase drain (finish input → finalize analyzer → await resultTask with 2s timeout → cleanup with sessionID guard); `stopRecognitionLocked()` is the synchronous force-stop used internally by `startRecognition()`
- `AudioCaptureService` uses `OSAllocatedUnfairLock<State>` protecting `audioFile`, `onAudioBuffer`, `onAudioLevel` from data races between main thread and audio render thread; `stopCapture()` clears all callbacks symmetrically
- When using `withUnsafeContinuation` with competing Tasks (drain vs timeout), cancel the losing task to prevent resource leaks
- LLM engines are `nonisolated final class: @unchecked Sendable` — safe to call from any isolation context

### State & Lifecycle
- `RecordingSession.audioFilePath` stores relative filename only — use `audioFileURL` computed property to reconstruct full path
- `RecordingViewModel.stopRecording()` is sync (non-blocking) — sets `.stopping` immediately; does NOT cancel in-flight `summaryTask` — `drainTask` awaits it before persist; `persistSession()` is idempotent via `sessionPersisted` flag — `drainTask` already calls it, so ContentView.onChange should NOT call it again
- Periodic summarization: `summaryTimer` fires at configurable interval; `triggerPeriodicSummary()` uses `periodicWindowCount` for window-aligned `coveringFrom`/`coveringTo` (don't use `ceil(elapsedTime)` — timer drift causes off-by-one window); `nextPeriodicCoveringFrom` tracks accumulated windows when previous ones are skipped
- Use `1 << Int(x)` not `Int(pow(2, x))` for power-of-2 values — avoids floating-point precision issues at large exponents
- **`KeychainService`**: `nonisolated enum` for secure string storage in macOS Keychain; `save(key:value:) -> Bool` (delete-then-add pattern), `load(key:) -> String?`, `delete(key:) -> Bool`; uses `kSecClassGenericPassword`, `kSecAttrService` = bundle ID, `kSecAttrAccount` = key name, `kSecAttrAccessibleWhenUnlocked`; no special entitlement needed for sandboxed apps
- **`CrashLogService`**: Uses MetricKit (`MXMetricManagerSubscriber`) to receive crash diagnostics from PREVIOUS session on NEXT launch; `nonisolated final class` inheriting from `NSObject` with singleton `shared` instance; `install()` registers with `MXMetricManager.shared`; `didReceive(_: [MXDiagnosticPayload])` extracts `MXCrashDiagnostic` (termination reason, exception type/code, signal, VM region info, call stack tree JSON); same crash log directory/file (`~/Library/Application Support/notetaker/CrashLogs/last_crash.log`), same `checkPreviousCrash()` behavior
- `TranscriptExporter` formats segments as timestamped text and copies to `NSPasteboard`; `formatAsText(title:segments:)` supports optional title header
- Graceful quit: `applicationShouldTerminate` returns `.terminateLater` if recording, waits for `awaitDrainCompletion()`, then replies `true`
- **Force-quit detection**: `RecordingSession.isPartial: Bool` marks sessions saved during force-quit (transcript may be incomplete)
- **Scheduling & Calendar Integration**: `SchedulerViewModel` orchestrates scheduled recordings; `SchedulerService` (singleton, `SchedulerServiceProtocol`) manages `UNUserNotificationCenter`; `CalendarService` reads `EKEvent`s via EventKit
- **Auto-start**: Timer polling (30s) in `SchedulerViewModel.checkAndFireDueRecordings()` handles foreground auto-start independently of notifications; `willPresent` is pure presentation only
- **Direct callback**: `handleFire()` calls `RecordingViewModel.startRecording()` directly via weak ref (no notification relay); includes auto-start permission prompt via `NSAlert.showsSuppressionButton` + `UserDefaults("autoStartRecordingAllowed")`
- **Duration-end timer**: `RecordingViewModel.durationEndTimer` fires after scheduled duration; shows `.alert` asking stop/continue; pauses/resumes with recording; uses `remainingDurationSeconds` tracking
- **`ScheduledRecordingInfo`**: Lightweight `Sendable` struct decoupling `RecordingViewModel` from SwiftData; carries `id`, `title`, `durationMinutes`
- **Duplicate import detection**: Uses `calendarEventIdentifier` (EKEvent.eventIdentifier) first, falls back to title+time heuristic (60s tolerance)
- **Recurrence mapping**: `CalendarService.mapRecurrenceRule()` maps `EKRecurrenceRule` to `RepeatRule`; only `interval == 1`; weekday detection via `Set<EKWeekday>` equality
- **SchemaV6**: Adds `calendarEventIdentifier: String? = nil` to `ScheduledRecording`, `scheduledRecordingID: UUID? = nil` to `RecordingSession`

### Accessibility (VoiceOver)
- `AccessibilityHelpers` (`nonisolated enum` in `Services/`) — pure functions for audio level description, duration formatting, recording state, session description; used by `AudioLevelBar`, `MenuBarView`, `TranscriptSegmentRow`, `SessionListView`
- `.accessibilityElement(children: .combine)` on composite rows (`TranscriptSegmentRow`, `SessionRowView`); `.accessibilityElement(children: .contain)` on `SummaryCardView`
- `.accessibilityHidden(true)` on decorative elements (pulsing dot, pause icon, dot separators)
- `.accessibilityAddTraits(.updatesFrequently)` on real-time data (audio level bar, timer display)
- `.accessibilityHint` on MenuBarView recording control buttons (start/stop/pause/resume)
- `.accessibilityLabel` + `.accessibilityAddTraits(.isSelected)` on `DateFilterChip`

## Architecture

Three-layer architecture: Views → ViewModels → Services, with SwiftData `@Model` classes for persistence.

- **`notetaker/`** — Main app target
  - `notetakerApp.swift` — Entry point, shared `ModelContainer`, `MenuBarExtra`, `Settings` scene
  - `ContentView.swift` — `NavigationSplitView` (sidebar session list + detail routing)
  - `Models/` — SwiftData models (`RecordingSession`, `TranscriptSegment`, `SummaryBlock`, `ScheduledRecording`), config types (`LLMConfig`, `SummarizerConfig`, `LLMModelProfile`, `VADConfig`, `OverallSummaryMode`, `RepeatRule`), ephemeral types (`ChatMessage`), schema versioning (`Schemas/` V1–V6)
  - `Services/` — Protocol-based engines (`ASREngine`, `LLMEngine`) with multiple implementations (including `FoundationModelsEngine` for Apple Intelligence), `AudioCaptureService`, `AudioPlaybackService`, `AudioExporter`, `SummarizerService`, `BackgroundSummaryService`, `SummaryMarkdownFormatter`, `ChatService`, `PromptBuilder`, `KeychainService`, `CrashLogService`, `SchedulerService`, `CalendarService`, `AccessibilityHelpers`
  - `ViewModels/` — `RecordingViewModel` (`@Observable`) — central state machine for recording lifecycle; `SchedulerViewModel` — scheduled recordings + calendar integration
  - `DesignSystem.swift` — `DS` enum (spacing, typography, colors, radius, layout tokens)
  - `Views/` — SwiftUI views including `SettingsView` (4-tab layout: `SettingsTab`, `ModelsSettingsTab`, `AboutTab`), `ScheduleView`, `ScheduleEditorView`, `PrivacyDisclosureView`, `SummaryCardView`, `TranscriptSegmentRow`, `AudioLevelBar`, `ResizeHandle`, `VerticalResizeHandle`, `ChatView`, `SettingsComponents` (reusable settings UI), `ViewModifiers`
- **`notetakerTests/`** — Swift Testing (`@Test`, `#expect`); ~65 test files; `Mocks/` has `MockASREngine`, `MockLLMEngine`, `MockSchedulerService`, per-suite `MockURLProtocol` subclasses; `Helpers/` has `BufferFactory` and `FileAudioSource`
- **`notetakerUITests/`** — XCTest UI tests (light/dark mode via `runsForEachTargetApplicationUIConfiguration`)
- **`scripts/`** — `increment_build_number.sh`
- **`docs/`** — `PRIVACY_POLICY.md`, `APP_STORE_PRIVACY_CHECKLIST.md`, specs (SPEC-001 through SPEC-005)

## Testing Gotchas

- Swift Testing `@Test` functions are always `nonisolated` regardless of `SWIFT_DEFAULT_ACTOR_ISOLATION` — use `@MainActor @Test` when testing MainActor-isolated types (`@Observable` ViewModels, SwiftData `mainContext`); use `ModelContext(container)` instead of `container.mainContext` in test helpers
- ASR integration tests need `.serialized` — `SpeechAnalyzer` may have concurrent recognition constraints
- LLM engine tests use per-suite MockURLProtocol subclasses to avoid shared state in parallel execution; each suite uses `.serialized`
- `URLProtocol` strips `httpBody` during request processing — `MockURLProtocolBase.canonicalRequest` saves it via `URLProtocol.setProperty` before it's lost; `requestWithRestoredBody()` restores it in `startLoading()`
- Speech-dependent tests use `.enabled(if: SFSpeechRecognizer.authorizationStatus() == .authorized)` trait — properly skipped (not silently passing) when speech authorization unavailable
- Test bundle resources: `Bundle(for: TestBundleAnchor.self).url(forResource:withExtension:)`
- xcodebuild doesn't pipe test process stdout — write to `NSTemporaryDirectory()` (sandbox: `~/Library/Containers/<bundle-id>/Data/tmp/`)
- Use `mdfind -name "filename"` to locate files written by sandboxed test processes
- AVAudioEngine real-time rendering requires audio hardware — use `enableManualRenderingMode(.offline, ...)` for test utilities that play audio files; must explicitly connect `mainMixerNode` → `outputNode` in offline mode
- `DispatchQueue.main.asyncAfter` may not fire during `Task.sleep`-based polling in Swift Testing — use `DispatchQueue.global()` or avoid dispatch
- UI launch tests use `runsForEachTargetApplicationUIConfiguration = true` to test light/dark mode; do NOT delete
- **Close the app before running tests** — if the app is already running, UI tests attach to the existing instance instead of launching a fresh one, causing `Failed to terminate` errors and test failures
- **Two-tier test plans**: `UnitTests.xctestplan` (22 pure-logic suites, ~257 tests, <0.2s) is default for Cmd+U; `FullTests.xctestplan` (all suites + UI tests) for CI on PR to main; shared scheme at `xcshareddata/xcschemes/notetaker.xcscheme` associates both plans
- **Test plan gotcha**: Xcode auto-generated schemes don't support `-testPlan`; the explicit shared scheme with `shouldAutocreateTestPlan = "NO"` is required; verify with `xcodebuild -scheme notetaker -showTestPlans`
- 31 test suites use `.serialized` to prevent parallel UserDefaults/Keychain/URLProtocol/SwiftData/NSPasteboard contamination; ~746 tests total across ~64 test files; UnitTests plan excludes all serialized suites for fast local iteration

## CI Workflows

- **`ci.yml`**: Runs on PR/push to `main`/`release` on `macos-26` runner; builds with `CODE_SIGNING_ALLOWED=NO`; runs FullTests plan (unit + UI tests); caches DerivedData; filtered test output with last-50-lines on failure
- **`auto-merge.yml`**: Waits for `ci.yml` build-and-test to pass, runs Claude Code review, then merges; closes linked issues after merge
- **`codeql.yml`**: CodeQL analysis for release branch protection

## CI/CD & Branch Protection

- **Release branch** protected via GitHub ruleset (ID 14307671): requires PR, 1 approval, signed commits, status checks (`build-and-test`), CodeQL, no force push/deletion
- **GitHub-hosted runners** (`macos-26`) run macOS 26 natively — both build and tests execute successfully with `CODE_SIGNING_ALLOWED=NO`
- **Three CI workflows**: `ci.yml` (build + full test), `codeql.yml` (Swift security scanning), `auto-merge.yml` (Claude review + auto-merge)
- **GitHub rulesets API**: use `code_scanning` not `required_code_scanning`; `pull_request` rule requires all 5 boolean params; use `--input` with JSON not `-f` flags for nested objects
- `gh label create` must precede `gh issue edit --add-label` — labels must exist first

## Known Limitations

- Settings changes require app restart to take effect for LLM engine (engine created at init time); summarizer config changes update timer interval live
- VAD config changes take effect on next recording (VAD instance created per `startAudioPipeline()` call)
