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

# Run a specific test class
xcodebuild -scheme notetaker -configuration Debug -only-testing:notetakerTests/notetakerTests test

# Run UI tests
xcodebuild -scheme notetaker -configuration Debug -only-testing:notetakerUITests test
```

## Key Patterns & Gotchas

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types MainActor by default; use `nonisolated` for audio/ASR classes
- `PBXFileSystemSynchronizedRootGroup` — no pbxproj edits needed for new source files
- SwiftData persistence with `@Model` classes (`RecordingSession`, `TranscriptSegment`)
- MenuBarExtra does NOT inherit `.modelContainer` from WindowGroup — must share `ModelContainer` explicitly
- Never put SwiftData `fetch()` in a computed property used by SwiftUI body — use `@State` + `onAppear`/`onChange`
- Audio tap singleton: only ONE tap per `AVAudioEngine` bus; `AudioCaptureService` owns the tap
- SpeechAnalyzerEngine uses `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26+) — no time limit, native volatile/final results
- Slider seek: use `onEditingChanged` to defer `seek(to:)` — direct binding causes audio glitching
- `ASREngine` protocol includes `appendAudioBuffer(_:)` — never downcast to concrete engine type
- `SpeechAnalyzerEngine` uses serial `DispatchQueue` for thread safety — all mutable state (including `onResult`/`onError` callbacks) accessed through `queue`
- `AudioCaptureService` uses `OSAllocatedUnfairLock<State>` protecting `audioFile`, `onAudioBuffer`, `onWriteError` from data races between main thread and audio render thread
- `RecordingSession.audioFilePath` stores relative filename only — use `audioFileURL` computed property to reconstruct full path
- Timer callbacks on `@Observable` classes already run on main thread — do NOT wrap in `Task { @MainActor }`

## Architecture

- **`notetaker/`** — Main app target (SwiftUI)
  - `notetakerApp.swift` — App entry point, shared `ModelContainer`, `MenuBarExtra`
  - `ContentView.swift` — `NavigationSplitView` (sidebar + detail routing)
  - `Models/` — `AudioConfig`, `RecordingSession`, `TranscriptSegment` (SwiftData)
  - `Services/` — `ASREngine` protocol, `SpeechAnalyzerEngine`, `NoopASREngine` (fallback), `AudioCaptureService`, `AudioPlaybackService`, `RingBuffer`
  - `ViewModels/` — `RecordingViewModel` (`@Observable`)
  - `Views/` — `LiveRecordingView`, `SessionListView`, `SessionDetailView`, `PlaybackControlView`, `TranscriptView`, etc.
  - `Extensions/` — `TimeInterval+Formatting` (`.mmss`, `.compactDuration`, `.hhmmss`)
- **`notetakerTests/`** — Unit tests using Swift Testing (`@Test`, `#expect`)
  - `Mocks/` — `MockASREngine`
  - `Helpers/` — `BufferFactory` (synthetic PCM buffers), `FileAudioSource` (offline file-to-buffer rendering), `AudioFileReader` (shared audio file → buffer conversion)
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

## Known Limitations (flag for M2)

- `ModelContainer` init failure now logged and surfaced in UI, but needs schema migration plan for recovery
- Quit during active recording calls `stopRecording` via `AppDelegate.applicationWillTerminate` but needs more robust cleanup
