# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A macOS note-taking/transcription app with live ASR, audio recording/playback, and session history.

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
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types MainActor by default; use `nonisolated` for audio/ASR classes
- `PBXFileSystemSynchronizedRootGroup` — no pbxproj edits needed for new source files
- `import os` provides both `Logger` AND `OSAllocatedUnfairLock` — don't remove from files using either
- Entitlements: sandbox + audio-input + `files.user-selected.read-write` (needed for transcript export/file access)

### SwiftData & SwiftUI
- SwiftData persistence with `@Model` classes (`RecordingSession`, `TranscriptSegment`)
- MenuBarExtra does NOT inherit `.modelContainer` from WindowGroup — must share `ModelContainer` explicitly
- Never put SwiftData `fetch()` in a computed property used by SwiftUI body — use `@State` + `onAppear`/`onChange`
- Slider seek: use `onEditingChanged` to defer `seek(to:)` — direct binding causes audio glitching
- Extract frequently-updated `@Observable` properties into separate class (e.g., `ElapsedTimeClock` defined at top of `RecordingViewModel.swift`) to prevent invalidating unrelated views on timer tick
- Timer callbacks on `@Observable` classes already run on main thread — do NOT wrap in `Task { @MainActor }`
- Even with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, always add explicit `@MainActor` to `Task` closures that access UI state after an `await` suspension point — implicit isolation is fragile across refactors

### Audio & ASR
- Audio tap singleton: only ONE tap per `AVAudioEngine` bus; `AudioCaptureService` owns the tap
- SpeechAnalyzerEngine uses `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26+) — no time limit, native volatile/final results; MUST call `analyzer.finalizeAndFinishThroughEndOfInput()` when stopping — without it `transcriber.results` never terminates
- `ASREngine` protocol: `stopRecognition()` is `async` (enables result drain); `onResult` is `@Sendable async` closure; `appendAudioBuffer(_:)` — never downcast to concrete engine type
- `AudioCaptureService` records M4A/AAC by default (128kbps) with automatic WAV fallback — old `.wav` files still play fine (`AVAudioPlayer` is format-agnostic)

### Thread Safety
- `SpeechAnalyzerEngine` uses serial `DispatchQueue` for thread safety — all mutable state accessed through `queue`; `stopRecognition()` is async with 4-phase drain (finish input → finalize analyzer → await resultTask with 2s timeout → cleanup with sessionID guard); `stopRecognitionLocked()` is the synchronous force-stop used internally by `startRecognition()`
- `AudioCaptureService` uses `OSAllocatedUnfairLock<State>` protecting `audioFile`, `onAudioBuffer` from data races between main thread and audio render thread
- When using `withUnsafeContinuation` with competing Tasks (drain vs timeout), cancel the losing task to prevent resource leaks

### State & Lifecycle
- `RecordingSession.audioFilePath` stores relative filename only — use `audioFileURL` computed property to reconstruct full path
- `RecordingViewModel.stopRecording()` is sync (non-blocking) — sets `.completed` immediately, drains ASR + persists in background `drainTask`; `persistSession()` is idempotent via `sessionPersisted` flag to prevent double-insert from racing code paths
- `CrashLogService` uses async-signal-safe POSIX calls only — no Swift runtime in signal handlers; pre-computed C file path via `strdup()`; installed at app init; crash logs written to `~/Library/Application Support/notetaker/CrashLogs/last_crash.log`
- `TranscriptExporter` formats segments as timestamped text and copies to `NSPasteboard`; `formatAsText(title:segments:)` supports optional title header

## Architecture

- **`notetaker/`** — Main app target (SwiftUI)
  - `notetakerApp.swift` — App entry point, shared `ModelContainer`, `MenuBarExtra`, `MenuBarView`
  - `ContentView.swift` — `NavigationSplitView` (sidebar + detail routing)
  - `Models/` — `AudioConfig`, `RecordingSession`, `TranscriptSegment` (SwiftData)
  - `Services/` — `ASREngine` protocol, `SpeechAnalyzerEngine`, `NoopASREngine` (fallback), `AudioCaptureService`, `AudioPlaybackService`, `RingBuffer`, `CrashLogService` (POSIX signal + ObjC exception crash logging), `TranscriptExporter` (format/copy transcript to clipboard)
  - `ViewModels/` — `RecordingViewModel` (`@Observable`)
  - `Views/` — `LiveRecordingView`, `SessionListView`, `SessionDetailView`, `PlaybackControlView`, `TranscriptView`, `ControlBarMetrics` (layout constants enum), etc.
  - `Extensions/` — `TimeInterval+Formatting` (`.mmss`, `.compactDuration`, `.hhmmss`)
- **`notetakerTests/`** — Unit tests using Swift Testing (`@Test`, `#expect`)
  - `Mocks/` — `MockASREngine`
  - `Helpers/` — `BufferFactory` (synthetic PCM buffers), `FileAudioSource` (offline file-to-buffer rendering)
  - `Resources/` — `sample_speech.mp3` test fixture
  - `TestHelpers.swift` — shared `sampleSpeechURL()`, `TestBundleAnchor`, `TestError`
- **`notetakerUITests/`** — UI tests using XCTest (`XCUIApplication`)

## Testing Gotchas

- ASR integration tests need `.serialized` — `SpeechAnalyzer` may have concurrent recognition constraints
- Speech-dependent tests use `.enabled(if: SFSpeechRecognizer.authorizationStatus() == .authorized)` trait — properly skipped (not silently passing) when speech authorization unavailable
- Test bundle resources: `Bundle(for: TestBundleAnchor.self).url(forResource:withExtension:)`
- xcodebuild doesn't pipe test process stdout — write to `NSTemporaryDirectory()` (sandbox: `~/Library/Containers/<bundle-id>/Data/tmp/`)
- Use `mdfind -name "filename"` to locate files written by sandboxed test processes
- AVAudioEngine real-time rendering requires audio hardware — use `enableManualRenderingMode(.offline, ...)` for test utilities that play audio files; must explicitly connect `mainMixerNode` → `outputNode` in offline mode
- `DispatchQueue.main.asyncAfter` may not fire during `Task.sleep`-based polling in Swift Testing — use `DispatchQueue.global()` or avoid dispatch
- UI launch tests use `runsForEachTargetApplicationUIConfiguration = true` to test light/dark mode; do NOT delete
- **Close the app before running tests** — if the app is already running, UI tests attach to the existing instance instead of launching a fresh one, causing `Failed to terminate` errors and test failures

## Known Limitations (flag for M2)

- `ModelContainer` init failure now logged and surfaced in UI, but needs schema migration plan for recovery
- Quit during active recording: `applicationWillTerminate` calls sync `stopRecording()` which sets state + launches drain task, but process may exit before drain completes; M2 should use `applicationShouldTerminate` with `.terminateLater` for real async cleanup
