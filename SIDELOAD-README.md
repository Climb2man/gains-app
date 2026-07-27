# Gains — free-Apple-ID sideload fork

A fork of [RightNxw/gains-app](https://github.com/RightNxw/gains-app) modified so it can be built
without a Mac and installed on an iPhone with a **free** Apple ID (no $99/yr Apple Developer Program).

Build happens on GitHub's macOS runners. Installation happens from Windows via Sideloadly.

---

## Summary of what changed vs upstream

| Change | Why |
|---|---|
| `GainsWidget` target removed from `project.yml` | The widget's only channel to the app was the App Group `group.com.nxw.gains`. Apple does not issue App Groups to free personal teams. |
| `application-groups` removed from both entitlements files | Same reason. Cannot be provisioned on a free account. |
| `keychain-access-groups` removed from `Gains-Release.entitlements` | `KeychainStore.defaultAccessGroup` is `nil` on device, so iOS grants the app's automatic default group. Declaring one only risks a signing mismatch. |
| Bundle IDs `com.nxw.gains*` → `com.kevin.gains*` | Bundle IDs are globally unique; the upstream ID belongs to the original author. |
| `.github/workflows/build-ipa.yml` added | Builds an unsigned `.ipa` on a free `macos-15` runner. |

**Deliberately left untouched:** `Sources/Widget/**`, `GainsWidget.entitlements`, and
`Sources/Shared/WidgetShared.swift`. Restoring the widget on a paid account is a `git revert` of the
`project.yml` and entitlements changes, nothing more.

### What still works

Everything except the two lock-screen widgets: Whoop sync, food logging, barcode scanning, photo/AI
estimates, Apple Health weight import, journal, workouts, weight tracking, encryption at rest.

`NutritionStore.swift:360` still calls `WidgetSharedStore.write()`. With no App Group entitlement,
`UserDefaults(suiteName:) ?? .standard` falls back to standard defaults — the write succeeds and is
simply never read. Harmless, and it keeps the diff small.

---

## Commands

### Build (runs on GitHub, not your PC)

Push to `main`, or open the repo's **Actions** tab → **Build unsigned IPA** → **Run workflow**.
Takes roughly 5–15 minutes. Download `Gains-unsigned-ipa` from the finished run's Artifacts section
and unzip it to get `Gains-unsigned.ipa`.

### Install to iPhone (from Windows)

1. Install [Sideloadly](https://sideloadly.io) and Apple Devices (or iTunes) for the USB drivers.
2. Plug in the iPhone, trust the computer.
3. Drag `Gains-unsigned.ipa` into Sideloadly, enter your Apple ID, click Start.
4. On the iPhone: **Settings → General → VPN & Device Management** → trust your developer certificate.
5. Launch Gains.

### Local syntax checks (Windows, no Xcode needed)

```powershell
python -m pip install pyyaml
python -c "import yaml; [yaml.safe_load(open(f, encoding='utf-8')) for f in ['project.yml', '.github/workflows/build-ipa.yml']]"
python -c "import xml.dom.minidom as m; [m.parse(f) for f in ['Gains.entitlements','Gains-Release.entitlements']]"
```

---

## File descriptions

| File | Role |
|---|---|
| `.github/workflows/build-ipa.yml` | CI: xcodegen → xcodebuild unsigned → zip `Payload/` → upload `.ipa` artifact |
| `project.yml` | XcodeGen manifest. Defines the `Gains`, `GainsTests`, `GainsUITests` targets |
| `Gains.entitlements` | **Debug / simulator only.** HealthKit + bare keychain group (needed or `SecItem*` returns -34018) |
| `Gains-Release.entitlements` | **Device / sideload.** HealthKit only |
| `GainsWidget.entitlements` | Orphaned. Kept for restoring the widget on a paid account |
| `Sources/Services/KeychainStore.swift` | Keychain wrapper; `defaultAccessGroup` is `nil` on device |
| `Sources/Shared/WidgetShared.swift` | Snapshot structs + shared store. Falls back to `.standard` |
| `scripts/ship-testflight.sh` | Upstream TestFlight script. **Unused here** — requires a paid account |

---

## Notes and gotchas

- **The `.ipa` from CI is unsigned and will not install on its own.** Sideloadly re-signs it. This is
  by design: signing on the runner would mean uploading an Apple certificate as a GitHub secret.
- **Free certificates expire after 7 days.** The app stops launching until re-signed. AltStore can
  refresh over WiFi automatically; Sideloadly requires plugging in again. **Your data is not lost** —
  it stays in the app container and returns when you re-sign.
- **Three sideloaded apps maximum** per free Apple ID, and roughly 10 new app IDs per week.
- **HealthKit is the open risk.** It is kept in `Gains-Release.entitlements` on the assumption that a
  free personal team can provision it. If Sideloadly errors on the entitlement, delete these two lines
  from that file, re-run the workflow, and reinstall:
  ```xml
  <key>com.apple.developer.healthkit</key>
  <true/>
  ```
  Weight entry then becomes manual (`WeightStore.log(lb:)`); everything else is unaffected.
- **The repo must stay public** for free macOS runner minutes. It contains only source code — no
  credentials, no health data. Whoop tokens live in the iPhone Keychain and never touch the repo.
- **Whoop uses an unofficial private API.** Upstream's warning applies: linking your account is
  outside Whoop's developer terms and could get it rate-limited or banned.
- **OpenRouter is optional.** Without an API key, barcode scanning (Open Food Facts) and manual macro
  entry still work; AI text estimates and photo logging do not. Photo requests are pinned to the
  `.cheap` lane (`google/gemini-2.5-flash-lite`); text falls back to `perplexity/sonar`. Both model
  IDs are overridable in Settings.

---

## Not yet verified

The Swift code has **not been compiled** — that requires macOS, which is the whole reason for the CI
workflow. Validated so far on Windows: YAML syntax of `project.yml` and the workflow, XML syntax of
both entitlements files, and the resulting XcodeGen target graph (`Gains`, `GainsTests`,
`GainsUITests`; no dangling `GainsWidget` dependency). The first CI run is the real test.
