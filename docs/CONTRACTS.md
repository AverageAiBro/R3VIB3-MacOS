# R3VIB3 Derived Contracts

This document captures behavior observed from the codebase. It is meant to lock expectations for refactors.

## Entry Points
- App lifecycle: `LocalTranscribePasteApp` + `AppDelegate.applicationDidFinishLaunching`.
- Hotkeys: Carbon hotkeys (`HotkeyManager`) and event-tap hotkeys (`HoldHotkeyManager`).
- Status bar menu: `StatusBarController` menu items.

## Invariants
- Dictation requires microphone permission; paste actions require accessibility permission.
- Recording indicator state matches `AppState.isRecording` and `activeRecordingMode`.
- Transcription only runs after a successful recording stop.
- `R3VIB3/Models` is preferred over legacy `LocalTranscribePaste/Models` if present.

## Flows
### Toggle dictation (happy path)
1. Toggle hotkey or menu item calls `AppState.toggleDictation()`.
2. Recording starts via `AudioCaptureManager.startRecording()`.
3. On stop, audio is converted to 16k mono, transcribed by whisper-cli.
4. Transcript is stored, optionally copied, and paste-ready indicator shown.

### Toggle dictation (failure path)
- Missing microphone permission: show permissions window, log warning.
- Recording start/stop failure: show error message, leave indicator off.
- Transcription failure: show message derived from `TranscriptionError`.

### Hold-to-record (happy path)
- Event tap detects hold hotkey; `AppState.startHoldRecording()`
- On key release, `stopHoldRecording()` triggers transcription.

## Boundaries
- UI: Status bar, popovers, settings, permissions windows.
- Orchestration: `AppState`.
- Audio capture: `AudioCaptureManager`.
- Transcription: `TranscriptionManager` + `WhisperCLITranscriber`.
- Input/paste: `PasteManager`.
- Permissions: `PermissionsManager`.

## Time + Async Rules
- Transcription runs on a dedicated background queue.
- UI updates dispatched to main thread via `MainThreadRunner`.
- Hotkey event tap runs on CoreGraphics callback thread; actions hop to main.

## Optimization and UI contracts
- Only one recording/transcription is active at a time. Retry and Clear cannot race an in-flight job.
- The latest app-owned recording is retained for Retry, then deleted when replaced, cleared, or the app normally exits. External input URLs are never deleted by AppState.
- Intermediate resampled WAVs are deleted after engine completion, including asynchronous completion and errors; whisper output TXT files are cleaned up after the result is read.
- Conversion buffers are limited to 4,096 frames. Multi-channel input preserves the loudest-channel rule using a bounded analysis pass; conversion drains the final frames at EOF.
- Screenshot filenames preserve their full UUID suffix. Invalid names are ignored. Preview decoding runs on a background queue, caps the longest dimension at 384 pixels, and caches at most 24 images / 12 MiB. Dragging still supplies the original files.
- Hotkey publishers pass the emitted shortcut to Carbon registration instead of reading the previous SettingsStore value.
- Type-text paste is paced on a serial background queue and does not modify the clipboard. Clipboard paste restores the snapshot only if the clipboard change count still matches our write.
- Permissions refresh when the app becomes active. Launching the app never resets existing Accessibility permission.
- App chrome uses Death Eater’s neutral dark Liquid Glass palette. The app now requires macOS 26+, as approved by Reno. Window backing is clear, title bars are transparent, controls use regular interactive glass, and outer surfaces use clear glass. Reduce Motion, Reduce Transparency, and Increased Contrast are respected. The recording waveform updates at most 20 times per second.
- Selected-window screenshots use asynchronous ScreenCaptureKit at the filter’s native point/pixel scale, excluding the cursor and shadows. No full-display fallback is used. Capture failure produces a visible message and leaves no capture entry. Capture requests are serialized while the picker/capture is active.

## Optimization measurement (2026-10-10)

A synthetic 600-second, 44.1 kHz mono CAF was converted with standalone `swiftc -O` builds of the original converter at `05c1abe` and the updated converter. `/usr/bin/time -l` reported maximum resident sizes of 175,800,320 bytes and 14,155,776 bytes respectively (about 92% lower). Output was 9,599,686 frames before and the full 9,600,000 frames after at 16 kHz. This measures conversion only, not Whisper inference or whole-app memory. Timing is a single local run, not a speed guarantee.
