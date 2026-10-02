# Parrot

Dictation from the menu bar. Say "Oy" or tap Option, speak, and Parrot turns your speech into text on this Mac and pastes it into the field you're typing in. [parrot.ramihmd.com](https://parrot.ramihmd.com)

## What you get

- **Say the wake word.** Turn on **Listen for "Oy"** in the popover and pick a microphone. Start a sentence with "Oy" and Parrot types the rest when you pause for a second. Only the start of a sentence counts, so mentioning a parrot mid-sentence doesn't trigger it. "Parrot" also works, or pick your own word.
- **Tap Option to start and stop.** A short sound plays and a red dot appears on the parrot in the menu bar while Parrot listens. A hollow dot means it's writing the text down. Option-shortcuts and Option-clicks still work, because only a quick tap of Option on its own counts.
- **Paste where you are.** Parrot copies the text, presses Command-V for you, then puts your clipboard back. Clipboard managers skip the dictation.
- **History.** Every dictation, searchable, with the model used, recording length, and how long the text took.
- **Local models, your pick.** Parakeet Ultra by default. Switch in the popover.
- **Cleanup.** Apple's on-device model fixes punctuation and capitals and drops um and uh, in about a second. If its output strays from your words (it answered a dictated question in testing), Parrot pastes the original. History keeps both.
- **Vocabulary.** Names and jargon Parrot should spell your way, each with how it mishears them. Parakeet engines listen for the terms with FluidAudio's CTC boosting, aliases are swapped in every transcript, and cleanup gets them as spelling hints.
- **Call notes.** Record in the popover when a call starts. Parrot records your mic as "You" and everything the Mac plays as "Them", transcribes both as the call goes, and writes a summary with decisions and action items when you stop. Only text is kept. Use headphones: on speakers, the mic hears the other side too (Parrot drops obvious echoes).

## Models

| Model | Released | Languages | Notes |
|---|---|---|---|
| Parakeet Ultra (default) | Sep 2026, Moondream | 25 European | Parakeet v3 post-trained at full precision. 5.80% vs v3's 6.26% on the Open ASR Leaderboard's 7 English sets. |
| Phonon-2 | Sep 2026, Fermion Research | English | Parakeet v3 retrained to five values per weight. First load compiles for about a minute. |
| Parakeet Redux | Sep 2026, Moondream | 25 European | Ternary Parakeet v3, 178 MB. |
| Parakeet v3 | 2025, NVIDIA | 25 European | Detects the language. |
| Parakeet v2 | 2025, NVIDIA | English | |
| Apple Speech | macOS 26 | System language | Built in. No download. |

The Parakeet family runs on the Neural Engine through [FluidAudio](https://github.com/FluidInference/FluidAudio). Models download once to `~/Library/Application Support/FluidAudio/Models`.

### Adding a model

All models live in `Parrot/Engines/Engine.swift`. Write an actor that conforms to `TranscriptionEngine` (`prepare()` and `transcribe(_:)` on 16 kHz mono samples), then add a case to `EngineID` with a name, a description, and `make()`. The popover picker, Compare Models, and the eval test all read from `EngineID.allCases`.

For another FluidAudio model, the engine already exists: add a case that returns `ParakeetEngine(version: .theNewVersion)`.

## Comparing models

**One recording.** In History, right-click a dictation and choose **Compare Models…**. Parrot runs the saved recording through every model, one at a time. It shows each transcript, the time it took, and how far it differs from the original transcript.

**An eval set.** Right-click a dictation and choose **Add to Eval Set**. That copies the recording and its transcript to `~/Library/Application Support/Parrot/Eval`. Open the `.txt` and fix any wrong words, so it holds what you actually said. Then score every model:

```sh
TEST_RUNNER_PARROT_EVAL=1 xcodebuild -project Parrot.xcodeproj -scheme Parrot -destination 'platform=macOS' test -only-testing:ParrotTests/EngineEval
```

Add `TEST_RUNNER_PARROT_ENGINES=parakeetV2,phonon2` to score only some models. The report prints a WER, load time, transcription time, and speed per model, followed by every clip each model got wrong. It also lands in `$TMPDIR/ParrotEval/report.md`. WER ignores case and punctuation but not number formatting, so "12%" against "twelve percent" counts as errors.

Parrot keeps recordings for the latest 300 dictations, in `~/Library/Application Support/Parrot/Clips`.

## Permissions

- **Microphone**, asked for the first time you dictate.
- **System Audio Recording Only**, asked for the first time you record a call. If it's denied, the "Them" side stays silent. Change it in System Settings > Privacy & Security > Screen & System Audio Recording.
- **Accessibility**, to see the Option key in other apps and to press Command-V. Without it, Parrot only hears Option while its own popover is open, and it copies instead of pasting.

Debug and Release builds are both signed with the HMDFV Inc. Developer ID, so the grants survive rebuilds.

## Build

Requirements: macOS 26 or later, Xcode 26 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project Parrot.xcodeproj -scheme Parrot -destination 'platform=macOS' test
open Parrot.xcodeproj   # then Run
```

Parrot isn't sandboxed, because it presses Command-V in other apps. That means it can't ship on the Mac App Store.

The app icon is drawn in code. Edit `scripts/render-icon.swift` and run `swift scripts/render-icon.swift` from the repo root.

## Updates and releases

Same as Pacer. The app checks `https://parrot.ramihmd.com/appcast.xml` with [Sparkle](https://sparkle-project.org), using the same signing key as Pacer and Redpen. `scripts/make-dmg.sh` builds a signed disk image. `scripts/release.sh "notes"` notarizes it, publishes the GitHub release to `HMDRAMS-DEV/parrot`, adds it to `site/appcast.xml`, and deploys the site.

## License

MIT
