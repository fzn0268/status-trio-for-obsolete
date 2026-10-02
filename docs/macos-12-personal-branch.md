# The macOS 12 personal branch

`macos12-personal` runs Status Trio on one Monterey machine. It is a personal build, not
a path to public macOS 12 support: it is never pushed, never dispatched through CI, and
never merged back as a macOS 12 announcement. The public app stays macOS 15+.

Everything below is what that trade looks like in practice, so the next session does not
have to rediscover it.

## Toolchain

The machine has Xcode 14.2 — Swift 5.7.2 and the macOS 13.1 SDK — on macOS 12.6 (x86_64).
That single fact drives every other compromise on this branch:

- Swift 5.7 rejects the Swift 6-only syntax the mainline uses, and has no swift-testing.
- The 13.1 SDK cannot name an API newer than itself. `cannot find X in scope` here is
  evidence about the SDK, not about macOS 12, so an API that new is dropped rather than
  availability-gated, and `#available` purity is not a goal.
- The popover keeps the pre-Tahoe appearance on purpose, because the alternative is not
  shipping at all on that system.

Xcode 14.2 is not the default developer directory, so **every** build or test command
needs the prefix:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Build and run the bundle

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  STATUS_TRIO_LEGACY_MACOS=1 bash scripts/build-app.sh release
```

The result is `dist/StatusTrio.app`, ad-hoc signed, `minos 12.0`, declaring
`LSMinimumSystemVersion 12.0`. `STATUS_TRIO_LEGACY_MACOS=1` is the branch's escape hatch
in that script: it skips the SDK-26 guard, the Sparkle embed, and the `sdk` stamp rewrite.
The deployment-target assertion deliberately stays, so the binary and the bundle cannot
drift apart, and the release path never sets the flag — which is also why
`AGENTS.md`'s "the release workflow is the acceptance environment" rule does not apply
here. Verify a build against that file only on mainline.

Pass `no-open` as the second argument to build without quitting or launching the running
instance (`bash scripts/build-app.sh release no-open`).

The floor also travels into two release-side defaults: `release.json` declares
`min_system_version 12.0`, and `scripts/update-appcast.rb` now writes
`sparkle:minimumSystemVersion` 12.0 when it is not passed explicitly. Nothing on this
branch publishes an appcast, so both matter only if the branch is ever merged — and then
they go back to the published floor. `scripts/verify-platform-version.sh` keeps its 26
default and is a mainline check; it is not run here.

## What the branch gives up

Each loss is documented at its own call site, and the mainline behaviour is untouched.

| Feature | macOS 12 behaviour | Where |
| --- | --- | --- |
| Sparkle automatic updates | permanently disabled; the update UI keeps its call sites but never links the framework, because the dependency cannot be fetched from this machine | `App/UpdaterManager.swift` |
| Launch at login | greyed out with an explanation row — `SMAppService` is macOS 13, and a `SMLoginItemSetEnabled` helper bundle needs a Developer ID this repo does not have | `App/LaunchAtLoginManager.swift`, `settings.launchAtLogin.requiresMacOS13` |
| Microphone-in-use marker | reports nothing; the audio-process properties it read are newer than the SDK | `Audio/CoreAudioInputHardware.swift` |
| 6 GHz band | a 6 GHz network shows no band instead of a wrong one, because `CWChannelBand.band6GHz` is absent | `Models/WiFiFrequencyBand.swift` |
| Graded Wi-Fi glyph | the `wifi` symbol in the popover row and the network list draws at its default fill instead of one bar level per signal (`variableValue` is macOS 13). The menu bar icon is unaffected — the app renders its own arcs | `Compatibility/VariableValueSymbol.swift`, `Compatibility/SymbolAvailability.swift` |
| Battery time remaining | still reads "1h 30m", but through `DateComponentsFormatter`, which has no `locale` in this SDK, so the row follows the system locale instead of the app's language override | `UI/BatteryDetailsView.swift` |
| Gradient settings squircle | a flat tint, since `Color.gradient` is macOS 13 | `UI/Settings/SettingsChrome.swift` |
| Keyboard selection on icon cards | the cards stay reachable with Tab and still activate with Space, but the group cannot move its selection with the arrow keys (`onKeyPress` is macOS 14), and without `focusEffectDisabled()` the system draws its own ring over the card's | `Compatibility/SelectionKey.swift` |
| Wrapping action rows | a plain row the window can still compress, since `Layout` is macOS 13 | `UI/Settings/WrappingHStack.swift` |
| Auto-sizing onboarding and popover hosts | `NSHostingController.sizingOptions` is macOS 13, so the size is kept the older way | `UI/OnboardingWindowController.swift`, `UI/StatusBarController.swift` |
| About pane GitHub mark | no mark; `NSImage` cannot read the SVG until macOS 13 | `UI/Settings/AboutIcon.swift` |
| Pre-Tahoe design language | accepted deliberately, and it is the reason the SDK guard is skipped | `scripts/build-app.sh` |

Two mechanics also changed shape rather than disappearing: the `Duration` family became
plain `TimeInterval` seconds everywhere, and `Task.sleep(for:)` — which segfaults on the
first call in a binary built with `minos 12.0` — goes through
`Compatibility/TaskSleep.swift`.

## What the branch adds: display volume over Intel DDC/CI

Mainline drives an external display's volume through `IOAVService`, the Apple Silicon
audio-driver proxy. An Intel Mac with a discrete GPU has no such service — MonitorControl
reaches the same VCP over the framebuffer's I2C interface instead, and this branch ports
that mechanism so a display on an AMD or Intel GPU can be controlled here.

`Audio/DDCDisplayTransport.swift` keeps one class and two backends:

- **arm64** — `IOAVService`, unchanged from mainline.
- **x86_64** — `IOFBGetI2CInterfaceCount` / `IOFBCopyI2CInterfaceForBus` on the framebuffer
  whose EDID identifies the display, then `IOI2CSendRequest` with the MCCS frames.

Three details are what the port actually turned on, and none of them are obvious from the
spec:

1. **The framebuffer is found by EDID, not by name.** The audio device UID carries the
   display's identity block, e.g. `AppleGFXHDAEngineOutputDP:10001:0:{AC10-D07E-30393953}`.
   That block is EDID bytes 8…16 read as three little-endian integers and printed in
   uppercase hex, so `edidIdentityBlock(_:)` and `audioUID(_:matchesEDID:)` do the match.
   `DDCDisplayTransportTests` pins it with a synthetic EDID.
2. **A read must be its own transaction.** On the AMD framebuffer kext a single combined
   request either echoes the write back or returns the previous transaction's reply. The
   working exchange is one claim, two transactions: send the Get-Volume frame with
   `replyTransactionType = kIOI2CNoTransactionType`, wait 50 ms, then read with
   `sendTransactionType = kIOI2CNoTransactionType`, `replyTransactionType =
   kIOI2CSimpleTransactionType`, `replyAddress = 0x6F`, `replySubAddress = 0x51`, and
   `minReplyDelay = 40_000`. The existing `DDCVolumeReply` decoder reads the reply
   unchanged.
3. **The interface is claimed per exchange, not held.** Each read or write opens and closes
   the I2C interface, so MonitorControl and Status Trio can coexist on the same display.

Verified on this machine against a DELL S2316H on an AMD Radeon RX 480 over HDMI: the
display resolves, volume reads back 20/100, writing the same value is accepted, and the
slider moves the hardware. That path is why the slider is no longer dead on this branch.

Attribution: the x86_64 path follows MonitorControl's `IntelDDC` (MIT, © MonitorControl —
@JoniVR, @theOneyouseek, @waydabber and others, adapted from @reitermarkus), noted at the
top of the file.

## Test suite

`swift test` runs green locally: **1125 tests, 0 failures, 22 skipped.**

- `Package.swift` excludes the 59 files that `import Testing` whenever the manifest
  compiles with `swift(<5.9)`, because swift-testing needs the Swift 6 toolchain. Those
  tests do not run here at all; on the CI toolchain the exclusion list is empty.
- `Tests/StatusTrioCoreTests/ToolchainCompatibility.swift` shims the two XCTest/async APIs
  5.7 predates: `AsyncStream.makeStream` and `XCTestCase.fulfillment(of:timeout:)`. The
  shim waits on its own thread, because blocking the main thread with the callback form
  starves the main actor that is supposed to fulfil the expectations.
- Seven test helpers defaulted a `@MainActor` object. Swift 5.7 evaluates a default
  argument in a nonisolated context, so the default moved into the isolated body as
  `parameter ?? Type()`.
- Render assertions that measure what a *newer* system draws skip instead of failing or
  being deleted, through `Tests/StatusTrioCoreTests/LegacyMacOSSkip.swift`. Sixteen of
  them do: SVG as `NSImage`, the graded `wifi` fill, a focus-ring host per drawn button
  (macOS 12 hosts plain-style buttons as nothing at all), `NSHostingController.sizingOptions`,
  and the full-width key-view proxy the current design language realizes in a window. The
  remaining six skips are the environment-gated sheet writers, which also skip on mainline.

Keeping these as `XCTSkip`s rather than deletions is deliberate: the same sources stay
valid on a newer OS, so nothing has to be remembered or re-derived when the branch is
rebased.

## Local environment notes

- TeamViewer installs a Multi-output device, an aggregate (`'aagg'`) device. When macOS
  makes it the default output, the popover reports no default output device, because
  `VolumeMonitor`'s `validDefaultOutputDevice()` rejects aggregates. Left as it is: the
  gate is mainline behaviour, and the same gate is what stops the app from writing volume
  to a device that cannot take it.
- A display whose HDMI audio path exposes no CoreAudio `VolumeScalar` — the DELL here — has
  DDC as its only writable volume, so the DDC backend is chosen whenever the current device
  has no writable scalar.

## Standing constraints for anyone working on this branch

1. Do not push it, do not dispatch the release workflow, and do not cut a release from it.
   `gh` has no credentials on this machine; those actions belong to the user.
2. Do not "fix" the branch back onto the CI toolchain. Building with the macOS 26 SDK,
   keeping `#available` coverage of new APIs, and a green `publish=false` preflight are
   mainline requirements; here the local compiler is the oracle.
3. Record every verification you actually ran, and say plainly which ones this machine
   cannot run.
