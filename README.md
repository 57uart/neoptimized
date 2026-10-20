# neoptimized

Notes and tooling from cutting resource use on a MacBook Neo (A18 Pro, 8 GB RAM, macOS 26.5) on 2026-10-20. The aim was the smallest practical CPU/RAM footprint **with SIP left on**.

## Results

### System-wide, start of session vs end

| | Start | End |
|---|---|---|
| Swap used | 5.4 GB of 6 GB | 0.37 GB |
| Free memory (`memory_pressure`) | 26% | 55% |
| Compressed memory | ~16 GB held in 2.9 GB | 4.8 GB held in 1.6 GB |

The workloads differed (Zen was open at the start; Codex and Claude Code at the end), so treat this as the overall direction. The per-change figures below were measured at the time of each change and are more reliable.

### RAM saved per change

| Change | Saved | Basis |
|---|---|---|
| Zen → Safari / Search browser | ~1–1.5 GB | Zen measured 1–2 GB RSS; browser ~0.65 GB afterwards, tab-dependent |
| Spotlight indexing off (`mdutil -a -i off`) | ~630 MB | RSS of `mds_stores` + `mdworker_shared` |
| VS Code → Zed | ~300 MB | VS Code RSS |
| Spotlight app quit at login | 146 MB | `footprint` |
| Santa blocks (36 services) | ~250–300 MB RSS | per-service measurements, minus Santa's own ~52 MB |
| Desktop widgets removed | ~56 MB | Weather, Photos, Calendar extensions |
| BetterDisplay removed | 66 MB | RSS (HiDPI kept via the display override plist) |
| Misc (GrandPerspective, leftovers) | ~50–150 MB | RSS |
| **Total** | **~2.5–3 GB** | about a third of 8 GB |

Blocking `contextstored` matters less for its current size (~11 MB) than for its known Tahoe memory leak (reports of 30 GB+).

### CPU

| Change | Effect |
|---|---|
| paneru event-pump patch | idle 2.77% → 0.50%; wakeups ~2,400/min → ~130/min |
| Santa refusing blocked services | +0.5% Santa, +0.2% launchd |
| Spotlight indexing off | no indexing bursts (not measured as a steady rate) |
| **Net idle** | about −1.6 percentage points, plus far fewer wakeups |

### Disk

Removed Xcode (3.7 GB; Command Line Tools kept), VS Code (1.4 GB), Helium (338 MB) and ~900 MB of their app data: ~6.3 GB.

## What's in place

- **Window manager:** paneru, patched build at `~/.local/bin/paneru` (see below); Homebrew copy unlinked.
- **Apps:** Safari/Search browser, Zed, Rio terminal.
- **macOS UI:** window/Dock/Finder animations off, Dock effectively hidden (`autohide-delay 1000`), edge tiling off, Reduce transparency + Reduce motion on, solid `#292929` wallpaper.
- **Spotlight:** indexing off on all volumes; [`launchagents/local.quit-spotlight.plist`](launchagents/local.quit-spotlight.plist) quits the Spotlight app 20 s after login; ⌘Space / ⌥⌘Space and the menu bar icon disabled.
- **Santa:** silent-block rules from [`santa-rules.txt`](santa-rules.txt), applied with [`santa-rules.sh`](santa-rules.sh).

## Approaches tried, and what we learned

### `launchctl disable` with SIP on: doesn't stick
SIP makes launchd drop disable overrides for Apple services at every boot ("Ignoring enabled state due to rootless restrictions"). Only services on Apple's `RemovableServices` allowlist (`/System/Library/Sandbox/com.apple.xpc.launchd.rootless.plist`, e.g. `com.apple.Siri.agent`) survive. `bootout`, `remove` and `unload` are all refused while SIP is on, even as root.

### SIP off: works, but SIP back on undoes it
[`services.sh`](services.sh) / [`services.txt`](services.txt) disabled 35 services with SIP off, and the disables survived a reboot. Re-enabling SIP brought 33 of them back. Kept for reference; not in use.

### Rejected ideas
- **`csrutil enable --without launchd`** doesn't exist. The valid components are `kext fs debug dtrace nvram basesystem`.
- **Editing the `RemovableServices` allowlist:** it's on the sealed system volume, so this means permanently disabling the seal check. That's less protection than just leaving SIP off.
- **Reactive kill switch** (term7.info/kill-siri): launchd restarts killed services within ~2 s, so a kill loop just churns.
- **Dummy service owning an Apple endpoint name:** launchd silently ignores a third-party job's claim; Apple's job keeps the port.

### What works with SIP on: Santa (Endpoint Security)
[Santa](https://github.com/northpolesec/santa) refuses `exec` of blocked platform binaries (`platform:<signing id>` rules), so the service never starts. Trade-offs we measured:

- **Retries cost CPU.** If something keeps calling a blocked service, launchd retries it (about every 10 s, sometimes every second), and Santa does real work refusing each attempt. With 64 rules that was ~3.5% Santa + ~1% launchd. Unblocking every service retried more than 1.5×/min, and repeating until stable (unblocking a caller can wake its dependencies; it took 3 rounds), brought it down to **0.5% + 0.2%** with 36 rules.
- **So Santa only pays off for leaf services that nothing calls.** The Siri / Apple Intelligence group is too interconnected to block piecemeal.
- **Synchronous callers hang.** Blocking a service that something waits on freezes the caller:
  - `AppleSpell`: every spell-check request takes a ~1 s timeout.
  - `analyticsd`: **must never be blocked.** The ASL MessageTracer shim sends to `com.apple.analyticsd.messagetracer` synchronously while holding the logging lock, which froze System Settings → Privacy & Security.
- The full list of deliberately unblocked services and the reasons is at the bottom of `santa-rules.txt`.

Undo all Santa rules: `sudo ./santa-rules.sh remove` (or `sudo santactl rule --clean`).

### Telemetry
Analytics sharing was already off in Settings (`AutoSubmit = false`, `ThirdPartyDataSubmit = false`, Siri data sharing opted out). Apps still send CoreAnalytics events to `analyticsd`; the setting only controls upload.

## paneru patch

Idle CPU came from the event pump's backoff: the poll timeout grew by 1 ms per quiet pass and every event reset it, so it took ~2 minutes of total silence to reach the 500 ms cap. Measured: ~1.5 events/s (window-title changes) kept the schedule at ~32 passes/s.

The patch grows the timeout by ×1.5 per quiet pass, reaching the cap in 16 passes (~1.4 s). The trade-off: short internal timers can land up to ~half their delay late during quiet stretches (e.g. a 300 ms focus check at ~425 ms). Real events still wake the pump immediately.

- PR: https://github.com/karinushka/paneru/pull/433 (base `testing`)
- Fork/branch: `57uart/paneru` `fix/pump-timeout-backoff`; local clone `~/repos/paneru`.
- Also reported in the PR, not fixed: `regroup_stray_native_tabs` makes a synchronous accessibility call per app every second on the main thread (~27% of main-thread samples blocked).

Switch back to Homebrew once a release includes the fix:

```sh
brew link paneru && /opt/homebrew/bin/paneru reinstall
```

Any rebuilt or replaced paneru binary needs a fresh Accessibility approval (TCC keys ad-hoc binaries by cdhash). To test a dev build, launch it through launchd (`bootstrap` + `kickstart` a LaunchAgent); started from a terminal, TCC checks the terminal's permission instead.

## Measuring

Use real footprint, not RSS: `footprint -p <pid>` (own processes) and `memory_pressure`. For CPU, take a CPU-time delta over 60 s (`ps -o time=`) while the machine is idle, and use `top -o power -stats pid,cpu,power,idlew,command` for energy and wakeups.
