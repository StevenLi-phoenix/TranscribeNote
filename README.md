# Notetaker

A macOS note-taking and transcription app with live ASR, audio recording/playback, LLM-powered summarization, scheduled recordings, and session history — all local-first.

## Features

- **Live Transcription** — Real-time speech-to-text using Apple's SpeechAnalyzer (macOS 26+) with Voice Activity Detection
- **LLM Summarization** — Periodic and overall summaries via local or cloud LLMs (Ollama, OpenAI, Anthropic, LM Studio)
- **LLM Profile System** — Named model profiles assignable to roles (live summarization, overall summary, title generation)
- **Scheduled Recordings** — Timer-based and calendar-integrated scheduling with auto-start and duration limits
- **Multi-Clip Audio** — Pause/resume recording with automatic clip merging
- **Session Management** — Searchable, date-filterable session list with tagging support
- **Background Summaries** — Post-recording summarization independent of view lifecycle
- **Summary Editing** — Inline edit and guided regeneration of summaries
- **Privacy-First** — API keys in macOS Keychain, local LLM support, privacy disclosure UI
- **Crash Diagnostics** — MetricKit integration for previous-session crash reporting

## Requirements

- macOS 26.2+
- Xcode (Swift 5, SwiftUI)
- Optional: local LLM server (Ollama, LM Studio) for summarization

## Build & Test

```bash
# Build
xcodebuild -scheme notetaker -configuration Debug build

# Run all unit tests (Swift Testing framework)
xcodebuild -scheme notetaker -configuration Debug test

# Run a specific test suite
xcodebuild -scheme notetaker -configuration Debug -only-testing:notetakerTests/RingBufferTests test

# Run UI tests
xcodebuild -scheme notetaker -configuration Debug -only-testing:notetakerUITests test
```

> **Note:** Close the app before running tests — UI tests attach to running instances instead of launching fresh ones.

## Architecture

Three-layer architecture: **Views → ViewModels → Services**, with SwiftData `@Model` classes for persistence.

```
notetaker/
├── notetakerApp.swift          # Entry point, ModelContainer, MenuBarExtra, Settings
├── ContentView.swift           # NavigationSplitView (sidebar + detail)
├── DesignSystem.swift          # DS enum (spacing, typography, colors, radius tokens)
├── Models/                     # SwiftData models + config types
│   ├── RecordingSession        # Core session with segments, summaries, audio paths
│   ├── TranscriptSegment       # Timestamped speech segments
│   ├── SummaryBlock            # LLM-generated summaries (chunk + overall)
│   ├── ScheduledRecording      # Timed recording with repeat rules
│   ├── LLMConfig/Profile       # LLM connection config + named profiles
│   └── Schemas/                # V1–V6 migration plan
├── Services/                   # Protocol-based engines + utilities
│   ├── ASREngine               # Speech recognition protocol + SpeechAnalyzerEngine
│   ├── LLMEngine               # LLM protocol + Ollama/OpenAI/Anthropic engines
│   ├── AudioCaptureService     # Recording with VAD gating
│   ├── AudioPlaybackService    # Playback with seek
│   ├── AudioExporter           # Multi-clip merge via AVComposition
│   ├── SummarizerService       # Prompt building + LLM orchestration
│   ├── BackgroundSummaryService # Post-recording summary generation
│   ├── SchedulerService        # UNUserNotificationCenter scheduling
│   ├── CalendarService         # EventKit calendar import
│   ├── KeychainService         # Secure API key storage
│   └── CrashLogService         # MetricKit crash diagnostics
├── ViewModels/
│   ├── RecordingViewModel      # Central recording state machine
│   └── SchedulerViewModel      # Scheduled recordings + calendar
└── Views/                      # SwiftUI views
    ├── SessionListView         # Grouped-by-day session browser
    ├── SessionDetailView       # Transcript + summaries + playback
    ├── SettingsView            # Tabbed LLM config with privacy disclosure
    ├── ScheduleView            # Scheduled recording management
    └── ...                     # LiveRecordingView, TranscriptView, etc.

notetakerTests/                 # ~60 test files, ~737 tests
docs/                           # Privacy policy, App Store checklist, specs
scripts/                        # Build number increment
```

## Key Technical Details

- **Actor Isolation**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — audio/ASR/LLM classes use `nonisolated`
- **Thread Safety**: `OSAllocatedUnfairLock` for audio thread state, serial `DispatchQueue` for ASR engine
- **SwiftData Migration**: 6 schema versions (V1–V6) with lightweight migrations via `NotetakerMigrationPlan`
- **File Discovery**: `PBXFileSystemSynchronizedRootGroup` — no pbxproj edits needed for new source files
- **Audio Format**: M4A/AAC (128kbps) with automatic WAV fallback
- **Entitlements**: Sandbox + audio-input + user-selected files + network client + calendar access

## Default LLM Configuration

- Provider: `.custom` (OpenAI-compatible)
- Model: `qwen3-14b-mlx`
- Base URL: `http://localhost:1234/v1` (LM Studio)

## License

Private repository.
