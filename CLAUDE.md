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

# Run unit tests (Swift Testing framework)
xcodebuild -scheme notetaker -configuration Debug test

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
- Entitlements: sandbox + audio-input + `files.user-selected.read-write` + `network.client` (needed for LLM API calls)

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

### Audio & ASR
- Audio tap singleton: only ONE tap per `AVAudioEngine` bus; `AudioCaptureService` owns the tap
- SpeechAnalyzerEngine uses `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26+) — no time limit, native volatile/final results; MUST call `analyzer.finalizeAndFinishThroughEndOfInput()` when stopping — without it `transcriber.results` never terminates
- `ASREngine` protocol: `stopRecognition()` is `async` (enables result drain); `onResult` is `@Sendable async` closure; `appendAudioBuffer(_:)` — never downcast to concrete engine type
- `AudioCaptureService` records M4A/AAC by default (128kbps) with automatic WAV fallback — old `.wav` files still play fine (`AVAudioPlayer` is format-agnostic)

### LLM & Summarization
- `LLMEngine` protocol: `generate(prompt:config:) async throws -> String`, `isAvailable(config:) async -> Bool` — `nonisolated`, `AnyObject`, `Sendable`, injectable `URLSession` for testing; config param ensures engines check user-configured URLs, not hardcoded defaults
- Four implementations: `OllamaEngine`, `OpenAIEngine`, `AnthropicEngine`, `NoopLLMEngine` — created via `LLMEngineFactory.create(from:session:)`; `.custom` provider maps to `OpenAIEngine` (OpenAI-compatible API for LM Studio etc.)
- `SummarizerService` orchestrates: guard minTranscriptLength → build prompt via `PromptBuilder` → call LLM with retry (3 attempts, 10s/30s/60s backoff, only retries network/HTTP errors)
- `SummarizerService.summarizeInChunks()` yields `ChunkProgress` per time window; `summarizeOverall()` synthesizes chunk summaries into a single overall summary
- `SummarizerService.splitIntoChunks()` uses zero-based windows: window 0 = `[0, interval)`, window 1 = `[interval, 2*interval)` — segments assigned by `Int(startTime / intervalSeconds)`; `splitIntoChunksWithWindowIndices()` returns window indices for boundary calculations
- `PromptBuilder` uses shared `styleInstructions(style:task:)` helper for DRY style formatting; `constraintBlock(config:)` enforces no-preamble output and language compliance; `sanitizeLanguage()` strips newlines and limits to 50 chars to prevent prompt injection
- `AnthropicEngine` guards empty `apiKey` with `.notConfigured` error (unlike OpenAI which skips the header for local/keyless setups)
- `LLMHTTPHelpers` enum in `LLMEngine.swift` consolidates shared HTTP methods (`performRequest`, `validateHTTPResponse`, `decodeResponse`) — don't duplicate in individual engines
- Split LLM config: `liveLLMConfigJSON` (periodic during recording), `overallLLMConfigJSON` (post-recording overall/chunked), `llmConfigJSON` (legacy fallback); `SessionDetailView.loadOverallLLMConfig()` tries keys in order: overall → live → legacy
- `LLMConfig` and `SummarizerConfig` stored as JSON in `@AppStorage`; use `.fromUserDefaults(key:)` static methods to load — don't duplicate loading logic; `LLMSettingsTab` accepts `configKey`/`fallbackKey` parameters for dynamic `@AppStorage` binding
- Default config: `.custom` provider, `qwen3-14b-mlx` model, `http://localhost:1234/v1` (LM Studio)
- `SummaryBlock` stores `style` as `String` raw value (SwiftData can't store custom enums directly); use `summaryStyle` computed property; `isOverall: Bool` distinguishes overall summaries from chunk summaries

### Thread Safety
- `SpeechAnalyzerEngine` uses serial `DispatchQueue` for thread safety — all mutable state accessed through `queue`; `stopRecognition()` is async with 4-phase drain (finish input → finalize analyzer → await resultTask with 2s timeout → cleanup with sessionID guard); `stopRecognitionLocked()` is the synchronous force-stop used internally by `startRecognition()`
- `AudioCaptureService` uses `OSAllocatedUnfairLock<State>` protecting `audioFile`, `onAudioBuffer` from data races between main thread and audio render thread
- When using `withUnsafeContinuation` with competing Tasks (drain vs timeout), cancel the losing task to prevent resource leaks
- LLM engines are `nonisolated final class: @unchecked Sendable` — safe to call from any isolation context

### State & Lifecycle
- `RecordingSession.audioFilePath` stores relative filename only — use `audioFileURL` computed property to reconstruct full path
- `RecordingViewModel.stopRecording()` is sync (non-blocking) — sets `.stopping` immediately; does NOT cancel in-flight `summaryTask` — `drainTask` awaits it before persist; `persistSession()` is idempotent via `sessionPersisted` flag — `drainTask` already calls it, so ContentView.onChange should NOT call it again
- Periodic summarization: `summaryTimer` fires at configurable interval; `triggerPeriodicSummary()` uses `periodicWindowCount` for window-aligned `coveringFrom`/`coveringTo` (don't use `ceil(elapsedTime)` — timer drift causes off-by-one window); `nextPeriodicCoveringFrom` tracks accumulated windows when previous ones are skipped
- Use `1 << Int(x)` not `Int(pow(2, x))` for power-of-2 values — avoids floating-point precision issues at large exponents
- `CrashLogService` uses async-signal-safe POSIX calls only — no Swift runtime in signal handlers; pre-computed C file path via `strdup()`; installed at app init; crash logs written to `~/Library/Application Support/notetaker/CrashLogs/last_crash.log`
- `TranscriptExporter` formats segments as timestamped text and copies to `NSPasteboard`; `formatAsText(title:segments:)` supports optional title header
- Graceful quit: `applicationShouldTerminate` returns `.terminateLater` if recording, waits for `awaitDrainCompletion()`, then replies `true`

## Architecture

- **`notetaker/`** — Main app target (SwiftUI)
  - `notetakerApp.swift` — App entry point, shared `ModelContainer`, `MenuBarExtra`, `MenuBarView`, `Settings` scene, config loading
  - `ContentView.swift` — `NavigationSplitView` (sidebar + detail routing)
  - `Models/` — `AudioConfig`, `RecordingSession`, `TranscriptSegment`, `SummaryBlock` (SwiftData), `SummaryStyle`, `LLMProvider`, `LLMConfig`, `SummarizerConfig`
  - `Services/` — `ASREngine` protocol, `SpeechAnalyzerEngine`, `NoopASREngine`, `AudioCaptureService`, `AudioPlaybackService`, `RingBuffer`, `CrashLogService`, `TranscriptExporter`, `LLMEngine` protocol, `OllamaEngine`, `OpenAIEngine`, `AnthropicEngine`, `NoopLLMEngine`, `LLMEngineFactory`, `SummarizerService`, `PromptBuilder`
  - `ViewModels/` — `RecordingViewModel` (`@Observable`)
  - `Views/` — `LiveRecordingView`, `SessionListView`, `SessionDetailView`, `PlaybackControlView`, `TranscriptView` (supports `scrollToTime` binding for jump-to-segment), `ControlBarMetrics`, `SummaryCardView` (tap timestamp to scroll transcript), `SettingsView` (Live LLM / Overall LLM / Summarization tabs with language picker)
  - `Extensions/` — `TimeInterval+Formatting` (`.mmss`, `.compactDuration`, `.hhmmss`)
- **`notetakerTests/`** — Unit tests using Swift Testing (`@Test`, `#expect`)
  - `Mocks/` — `MockASREngine`, `MockLLMEngine`, `MockURLProtocol` (per-engine subclasses: `OllamaMockProtocol`, `OpenAIMockProtocol`, `AnthropicMockProtocol`)
  - `Helpers/` — `BufferFactory` (synthetic PCM buffers), `FileAudioSource` (offline file-to-buffer rendering)
  - `Resources/` — `sample_speech.mp3` test fixture
  - `TestHelpers.swift` — shared `sampleSpeechURL()`, `TestBundleAnchor`, `TestError`
- **`notetakerUITests/`** — UI tests using XCTest (`XCUIApplication`)

## Testing Gotchas

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

## Known Limitations

- API key stored in plaintext `UserDefaults` — should move to Keychain for production
- `ModelContainer` init failure now logged and surfaced in UI, but needs schema migration plan for recovery
- Settings changes require app restart to take effect for LLM engine (engine created at init time); summarizer config changes update timer interval live
- API keys stored in plaintext in two config keys (`liveLLMConfigJSON`, `overallLLMConfigJSON`) — doubles surface area vs single key; both should move to Keychain
