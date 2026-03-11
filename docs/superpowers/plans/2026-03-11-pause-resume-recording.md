# Pause/Resume Recording Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add pause/resume capability to the recording flow, allowing users to pause and continue recording within a single session.

**Architecture:** Multi-clip approach — each pause/resume cycle creates a new audio file and ASR session. `RecordingSession` stores multiple audio file paths. Transcript timestamps are cumulative across clips (offset by previous clips' duration) so display, summarization, and seeking work naturally. Only playback needs a reverse mapping (cumulative time → clip + local time).

**Tech Stack:** Swift 5, SwiftUI, SwiftData, AVFoundation, SpeechAnalyzer (macOS 26+)

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `Models/Schemas/SchemaV4.swift` | Schema snapshot with `audioFilePaths` on RecordingSession |
| Modify | `Models/Schemas/NotetakerMigrationPlan.swift` | Add V3→V4 lightweight migration |
| Modify | `Models/RecordingSession.swift` | Add `audioFilePaths: [String]`, `audioFileURLs` computed property |
| Modify | `ViewModels/RecordingViewModel.swift` | Add `.paused` state, `pauseRecording()`, `resumeRecording()`, clip offset tracking |
| Modify | `Views/RecordingControlView.swift` | Add pause/resume buttons |
| Modify | `Views/LiveRecordingView.swift` | Wire pause/resume callbacks |
| Modify | `ContentView.swift` | Handle `.paused` state in detail view |
| Modify | `Services/AudioPlaybackService.swift` | Multi-clip sequential playback with cross-clip seeking |
| Modify | `Views/SessionDetailView.swift` | Load multi-clip audio for playback |
| Modify | `notetakerApp.swift` | Handle `.paused` in graceful quit + MenuBarView |

## Chunk 1: Data Model + ViewModel

### Task 1: SchemaV4 + RecordingSession Update

**Files:**
- Create: `notetaker/Models/Schemas/SchemaV4.swift`
- Modify: `notetaker/Models/Schemas/NotetakerMigrationPlan.swift`
- Modify: `notetaker/Models/RecordingSession.swift`
- Modify: `notetaker/notetakerApp.swift`

- [ ] **Step 1: Create SchemaV4** — Copy V3, add `audioFilePaths: [String] = []` to RecordingSession snapshot
- [ ] **Step 2: Update NotetakerMigrationPlan** — Add V3→V4 lightweight migration, add V4 to schemas array
- [ ] **Step 3: Update live RecordingSession** — Add `audioFilePaths: [String] = []` property, add `audioFileURLs: [URL]` computed property that combines both fields for backward compat
- [ ] **Step 4: Update notetakerApp ModelContainer** — No change needed (uses migration plan, auto-discovers schema)
- [ ] **Step 5: Build verification** — `xcodebuild -scheme notetaker -configuration Debug build`

### Task 2: RecordingState + ViewModel Pause/Resume

**Files:**
- Modify: `notetaker/ViewModels/RecordingViewModel.swift`

Key state additions:
- `RecordingState.paused` case
- `clipTimeOffset: TimeInterval` — sum of previous clips' elapsed durations
- `pausedElapsedTime: TimeInterval` — clock value at moment of pause
- `recordedAudioFilePaths: [String]` — collected during recording for session persist

Logic:
- `pauseRecording()`: stop ASR (4-phase drain), stop audio capture, stop timers, save clip file path, save elapsed time, set `.paused`
- `resumeRecording()`: set `clipTimeOffset = pausedElapsedTime`, start new audio pipeline (new file + new ASR session), restart timers, set `.recording`
- `handleTranscriptResult`: add `clipTimeOffset` to ASR timestamps
- `stopRecording()`: handle both `.recording` and `.paused` states
- `persistSession()`: save `recordedAudioFilePaths` to session
- Summary timer: pause on pause, resume on resume

- [ ] **Step 1: Add `.paused` to RecordingState**
- [ ] **Step 2: Add clip tracking state** — `clipTimeOffset`, `pausedElapsedTime`, `recordedAudioFilePaths`
- [ ] **Step 3: Implement `pauseRecording()`** — async, drains ASR, stops capture, saves state
- [ ] **Step 4: Implement `resumeRecording()`** — starts new pipeline, restores timer from offset
- [ ] **Step 5: Offset ASR timestamps** — in `handleTranscriptResult`, add `clipTimeOffset`
- [ ] **Step 6: Update `stopRecording()`** — handle `.paused` state (no ASR to drain)
- [ ] **Step 7: Update `persistSession()`** — save `recordedAudioFilePaths` to session
- [ ] **Step 8: Update `dismissCompletedRecording()`** — reset new state fields
- [ ] **Step 9: Build verification**

## Chunk 2: UI + Playback

### Task 3: RecordingControlView + LiveRecordingView + ContentView

**Files:**
- Modify: `notetaker/Views/RecordingControlView.swift`
- Modify: `notetaker/Views/LiveRecordingView.swift`
- Modify: `notetaker/ContentView.swift`
- Modify: `notetaker/notetakerApp.swift` (MenuBarView + AppDelegate)

RecordingControlView changes:
- Accept `onPause` and `onResume` callbacks
- During `.recording`: show pause button (pause.circle) alongside stop
- During `.paused`: show resume button (play.circle) + "Paused" indicator + elapsed time (frozen)

- [ ] **Step 1: Update RecordingControlView** — add pause/resume callbacks and UI states
- [ ] **Step 2: Update LiveRecordingView** — wire pause/resume to ViewModel
- [ ] **Step 3: Update ContentView** — show LiveRecordingView during `.paused` state
- [ ] **Step 4: Update MenuBarView** — show paused state, add pause/resume buttons
- [ ] **Step 5: Update AppDelegate** — handle `.paused` in graceful quit
- [ ] **Step 6: Build verification**

### Task 4: AudioPlaybackService Multi-Clip Support

**Files:**
- Modify: `notetaker/Services/AudioPlaybackService.swift`

- [ ] **Step 1: Add `loadMultiple(urls:)`** — load all clips, compute total duration and clip boundaries
- [ ] **Step 2: Implement cross-clip seeking** — map cumulative time to (clipIndex, localTime)
- [ ] **Step 3: Implement sequential playback** — auto-advance to next clip on finish
- [ ] **Step 4: Update `play()`/`pause()`/`stop()`** — work with multi-clip state

### Task 5: SessionDetailView Multi-Clip Wiring

**Files:**
- Modify: `notetaker/Views/SessionDetailView.swift`

- [ ] **Step 1: Use `audioFileURLs`** — load multiple files into playback service
- [ ] **Step 2: Build + manual test verification**

## Chunk 3: Commit

- [ ] **Step 1: Commit all changes**
