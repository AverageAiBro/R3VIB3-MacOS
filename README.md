# R3VIB3

![R3VIB3 Header](docs/R3VIBEHeader.jpeg)

Local-only macOS menu bar dictation app designed for seamless transcription across your local Mac and remote desktop sessions. Most dictation tools don’t paste reliably into RDP clients — R3VIB3 does.

## Requirements

macOS 26 or later. Build with Xcode 26 / Swift 6.2 or later. App chrome uses native Liquid Glass, matching Death Eater’s neutral black glass and capsule controls. Earlier macOS versions are no longer supported.

## Development improvements
- Transparent dark-glass settings and permissions, capsule controls, selectable transcript, and native glass recording/screenshot overlays. Reduced Motion and Increased Contrast are respected; Reduce Transparency makes window backing opaque.
- Audio conversion uses bounded buffers and removes intermediate WAV/TXT files after transcription.
- Screenshot previews are downsampled and cached; selections survive capture-list reloads.
- Shortcut changes take effect immediately, with overlapping dictation/retry requests prevented.
- Type-text paste runs off the UI thread and uses corrected key mappings with Unicode support.

## Build and run
1. Open `LocalTranscribePaste.xcodeproj` in Xcode.
2. Select the `LocalTranscribePaste` target (builds the R3VIB3 app).
3. Build and run (Debug).

The app runs as a menu bar item with the R3VIB3 icon.

## Permissions
On first launch, the app shows a permissions checklist window.

Enable:
- **Microphone**: System Settings > Privacy & Security > Microphone
- **Accessibility**: System Settings > Privacy & Security > Accessibility

If you change permissions, quit and relaunch the app.

## Whisper.cpp binary and model
This project uses the whisper.cpp CLI binary (default engine) and keeps models in Application Support.

### Whisper CLI binary
The repository includes a universal whisper.cpp CLI binary. If updating it:
- Source file path: `LocalTranscribePaste/Resources/whisper/whisper-cli`
- Ensure the binary is **executable** (`chmod +x whisper-cli`).
- Build a **universal** binary (Apple Silicon + Intel) and replace the bundled binary.

The app looks for the binary inside its bundle as `whisper-cli`.

### Model file
Default model path:
```
~/Library/Application Support/R3VIB3/Models/ggml-base.en.bin
```

Steps:
1. Create the folder if it does not exist.
2. Copy a whisper.cpp model file (`.bin`) into that folder.
3. In the app Settings, pick the model path you want to use.

## Microphone input

Recording currently uses the default microphone selected in **System Settings > Sound > Input**. Per-app device/channel selection is tracked as R3V-7; Settings shows the actual system input instead of inactive selectors.

## Development checks

```sh
swift test
bash scripts/verify.sh
SIGNING_MODE=adhoc bash scripts/package_app.sh debug
```

To package both architectures, set `ARCHES="arm64 x86_64"`. The packaging script resolves build paths through SwiftPM and keeps architecture outputs separate. Ad-hoc builds are for local testing; distribution still requires the release signing workflow.

## Usage
Default hotkeys:
- **Toggle Dictation**: Control + Option + Space
- **Paste Last Transcript**: Control + Option + V

Workflow:
1. Press Toggle Dictation to start recording.
2. Press Toggle Dictation again to stop and transcribe.
3. A popover shows the transcript with actions: Copy, Paste, Clear, Retry.
4. Use Paste Last Transcript hotkey to paste into the active app.

## Launch at login
In Settings, enable **Launch at login** to start R3VIB3 automatically when you sign in.


## Remote desktop notes (Microsoft Remote Desktop)
- Enable clipboard sharing in the RDP client.
- If Cmd+V does not paste into the remote session, switch to **Ctrl+V** in Settings.
- If clipboard paste is blocked, enable **Type** mode (character-by-character typing).

## Logs
The app uses `os_log` for audio start/stop, transcription, paste actions, and permission status.

## Notes
- Transcription runs locally and offline.
- The app never auto-inserts text into other apps.
