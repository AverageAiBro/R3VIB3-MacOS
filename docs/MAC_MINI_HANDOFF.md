# R3VIB3 development handoff — 2026-10-11

## Scope and source

Continue R3VIB3 development/testing on Reno's Mac mini, leaving DreamEater work on the MacBook untouched. Reno authorized committing/pushing the outstanding app work, installing Xcode on the Mini, verifying requirements, and preserving this development context.

- Official repository: https://github.com/AverageAiBro/R3VIB3-MacOS (public, unarchived).
- Published implementation: `058de02597fc0c96c76b16aee57fe012f44ac3c5`.
- Branch: `feat/r3v-3-optimize-facelift`. Keep `main` protected; no PR or release has been requested.
- Mini source clone: `/Users/r3no/Dev/R3VIB3-MacOS`.
- Mini task worktree: `/Users/r3no/Dev/R3VIB3-worktrees/r3v-3-optimize-facelift`.
- MacBook task worktree: `/Users/renodelacasas/Dev/R3VIB3-worktrees/r3v-3-optimize-facelift`.
- Work tracking: dedicated Linear **R3VIB3** team, **R3VIB3 macOS Facelift** project, **Optimization and facelift** milestone. This dedicated convention was explicitly requested and supersedes the global AAB team default for this project.

Migration: [R3V-13](https://linear.app/mstr-apps/issue/R3V-13). Toolchain preparation: [R3V-14](https://linear.app/mstr-apps/issue/R3V-14). Implementation/review: [R3V-3](https://linear.app/mstr-apps/issue/R3V-3). Update the [project status document](https://linear.app/mstr-apps/document/project-status-dd82041b0082) after each session.

## Accepted decisions and implementation

Reno approved a **macOS 26 minimum**. The Swift package requires tools 6.2 or later and uses Swift language mode 5; a broad concurrency migration was not part of the request.

The native facelift follows the local DreamEater/Death Eater reference: dark neutral palette, clear window glass with black 0.22 tint over black 0.24 fill, regular interactive capsule buttons, neutral 0.82 accent, transparent title bars, and native dark dialogs. Shared `R3VTheme` covers Settings, permissions, transcripts, recording indicators and screenshot strips. Reduce Motion, Reduce Transparency and Increase Contrast are respected. Isolated screenshots establish layout; Reno's live desktop/refraction acceptance remains outstanding.

The optimization pass includes bounded 4,096-frame audio conversion, bounded stereo-channel analysis and EOF draining; temporary WAV/TXT cleanup; retained recording for Retry followed by cleanup; one active recording/transcription; immediate hotkey updates; off-main typed paste with corrected keycodes/Unicode; guarded clipboard restoration; stable screenshot UUIDs; off-main downsampled previews with a bounded cache; original screenshot files for dragging; and one native Settings window supporting Command-comma and normal Quit/reopen.

Window screenshots now use asynchronous ScreenCaptureKit because the old capture API is unavailable for the approved OS target. Capture uses one selected window, the content-filter scale, excludes cursor/shadow, and guards overlapping picker/capture requests.

`README.md` and `docs/CONTRACTS.md` describe behavior. Do not silently restore obsolete APIs or add hidden fallback paths.

## Verified before migration

- All 17 Swift regression tests passed again before the implementation commit/push.
- `scripts/verify.sh` passed.
- Xcode Debug build and universal arm64/x86_64 package passed on the MacBook.
- Strict deep codesign verification passed; app and binary minimum OS are 26.0.
- Settings, permissions, shortcut sizing, Command-comma and quit/relaunch were inspected.
- Synthetic 600-second 44.1 kHz mono conversion: maximum RSS decreased from 175,800,320 to 14,155,776 bytes, with 9,600,000 output frames. This measures conversion only, not inference or whole-app memory.

## Mini setup and evidence

The Mini is Apple Silicon, running macOS 27.0.1. It had about 74 GiB available before setup. Its initial Command Line Tools (Swift 6.3.3, SDK 26.5) compiled the app but could not run XCTest (`no such module XCTest`). Xcode 27.0 (27A266a) was copied from the existing Apple-signed MacBook installation, passed strict deep signature verification on the Mini, and was installed at `/Applications/Xcode.app`. `xcode-select` now points to `/Applications/Xcode.app/Contents/Developer`. Its minimum macOS version is 26.6, satisfied by the Mini. The standard license and first-launch setup are complete; `xcodebuild -checkFirstLaunchStatus` passes. Reno also explicitly confirmed license acceptance. The active toolchain is Apple Swift 6.4 with macOS SDK 27.0. All 17 tests pass on the Mini, `scripts/verify.sh` passes, and the Xcode Debug project build succeeds. About 63 GiB remains available after setup and builds.

The Mini independently passed `scripts/verify.sh`, an arm64 Debug package build, and strict deep codesign verification using its original Command Line Tools before selecting Xcode. Selected MacBook test/build logs and the settings screenshot were also copied to `build/migration-r3v-13/macbook-evidence/`.

Mini verification evidence is under `build/migration-r3v-13/` in the task worktree. Generated binaries, models, screenshots and logs are intentionally excluded from Git.

The established default `ggml-base.en.bin` was downloaded from the source used by whisper.cpp's official model downloader into:

`/Users/r3no/Library/Application Support/R3VIB3/Models/ggml-base.en.bin`

Publisher SHA-256, verified after download:

`a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002`

The Mini's packaged Whisper CLI successfully transcribed whisper.cpp's public JFK sample with Metal enabled. This validates model loading and inference, not live microphone capture or paste permissions. Logs include `whisper-smoke.log` and `jfk-result.txt`.

Preview bundle ID: `com.averageaibro.r3vib3.preview`. Preview location: `R3VIB3.app` in the task worktree. Preserve the preview identity during testing so permissions do not accidentally target another build.

Full-toolchain verification logs: `xcode-tests.log`, `xcode-verify.log`, and `xcode-build.log` in `build/migration-r3v-13/`. First-launch and the full test suite are already complete.

Typical commands:

```sh
cd /Users/r3no/Dev/R3VIB3-worktrees/r3v-3-optimize-facelift
swift test
bash scripts/verify.sh
SIGNING_MODE=adhoc BUNDLE_ID=com.averageaibro.r3vib3.preview bash scripts/package_app.sh debug
codesign --verify --deep --strict R3VIB3.app
open R3VIB3.app
```

## Remaining runtime and product work

macOS Microphone, Accessibility and Screen Recording grants are host/app-specific. They were not transferred. Reno reported granting permissions on the MacBook, but the isolated preview still showed Enable after Refresh and no R3VIB3 microphone entry was observed. Do not treat permission grants for Codex as grants for R3VIB3. On the Mini, open the preview, trigger its permission requests, then grant the requested access in System Settings and refresh/relaunch as needed. Never edit TCC databases or weaken OS security.

After permissions are recognized, verify an actual recording/transcription/paste, Retry, selected-window screenshot capture, original-file drag, floating indicators and theme behavior against a real desktop backdrop.

[R3V-7](https://linear.app/mstr-apps/issue/R3V-7) remains open: per-app microphone/channel routing. Current recording deliberately uses the macOS default input; Settings reflects that behavior.

## RTX 3090 research context

Reno separately requested model research for a personal VM host with a 24 GB RTX 3090. The committed `docs/3090-dictation-research.md` contains primary citations and the evaluation plan. First English trial: Parakeet Unified English 0.6B, Canary-Qwen 2.5B, and local Whisper control. Qwen3-ASR 1.7B is an option for multilingual/context use. These are research candidates, not a deployment or measured recommendation for Reno's audio.

The proposed implementation seam is a configured, authenticated remote transcription adapter using the existing asynchronous `TranscriptionEngine` contract and retained-WAV lifecycle. No server, endpoint or remote upload behavior has been implemented. Keep local Whisper selectable. Next steps require VM/GPU access and a 30-clip plus silence evaluation for accuracy, latency and memory.

## Codex conversation continuity

The existing conversation is `01a12748-fb92-7f91-a00d-7041dd6398c3` (Unarchive r3vibe GitHub repo). It started as a projectless chat; direct remote handoff originally failed for that reason, independently of GitHub publication.

Using Codex's supported UI, the local task worktree was registered as a Git project and the conversation was attached to it. A matching remote project **R3VIB3 - Mini** was created at `/Users/r3no/Dev/R3VIB3-MacOS` on **Renos-Mac-mini.local**. The actual conversation has not yet moved as of this document's preparation. The environment is verified and ready. Initiate the existing-chat handoff from another authorized chat or supported UI. The handoff tool cannot move its own calling chat. This document preserves the substantive context independently of that transfer.


## Requested skills and model choice

Reno requested **GPT-6.1 Sol with high reasoning** for this development/setup conversation. Preserve that choice during handoff; do not change unrelated chats.

Reno also requested the Apple development skills supplied in DreamEater. Installed through Codex's skill-installer helper into `/Users/r3no/.codex/skills`, which previously contained only system skills:

- Swift Concurrency: `AvdLee/Swift-Concurrency-Agent-Skill` at `d5770817d2622e1585b1f7eaebc791a9cb0959c8`.
- Six Xcode build optimization skills: `AvdLee/Xcode-Build-Optimization-Agent-Skill` at `6bd7b596cd688b1127ded00e812b1b6937ec35d6`.
- SwiftUI Pro: `twostraws/swiftui-agent-skill` at `f9800713b24580bc444931949aad4519128605e8`. The upstream directory includes its nested Claude plugin copy.
- Twenty-five ASC skills: `rorkai/app-store-connect-cli-skills` at `9c7e769f09a18237c9bd9c70f70aef65f0cd0391`, linked by the official `rorkai/App-Store-Connect-CLI` README.

Total: **33 skill directories**. Homebrew's official `asc` formula installed CLI **5.10.0** at `/opt/homebrew/bin/asc`. No Apple account credentials, signing material, billing changes, releases or distribution operations were configured. Workflow-specific optional tools remain task-dependent. Skills are available on the next Mini Codex turn. Tracking: [R3V-15](https://linear.app/mstr-apps/issue/R3V-15).
