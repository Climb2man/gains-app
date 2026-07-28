# Next steps — installing Gains on the iPhone

Plain-English checklist. Everything before this point is done: the app is built and the file is ready.

**Built app:** `C:\Users\kevin\gains-build\ipa\Gains-unsigned.ipa` (3.78 MB)
**Rebuild anytime:** GitHub → this repo → **Actions** tab → *Build unsigned IPA* → **Run workflow**.
Download `Gains-unsigned-ipa` from the finished run and unzip it.

---

## Part 1 — Three installs on the PC

**Get iTunes and iCloud from apple.com, NOT the Microsoft Store.** AltStore does not work with the
Microsoft Store builds. Neither was installed as of 2026-07-27.

1. iTunes — <https://www.apple.com/itunes/download/win64> (Windows 64-bit link, not the Store button)
2. iCloud — <https://support.apple.com/en-us/HT204283>
3. AltServer — <https://altstore.io> → Windows → unzip → run `Setup.exe`

Restart the PC.

## Part 2 — AltStore onto the iPhone

4. Start menu → **AltServer** → right-click → **Run as administrator**. It lives in the system tray.
5. Plug the iPhone in, unlock, tap **Trust**, enter passcode.
6. Tray icon → **Install AltStore** → pick the iPhone → enter Apple ID.
7. iPhone: **Settings → General → VPN & Device Management** → tap the Apple ID → **Trust**.

## Part 3 — Gains onto the iPhone

8. Open the iCloud app on the PC, enable **iCloud Drive**.
9. Copy `Gains-unsigned.ipa` into the iCloud Drive folder.
10. iPhone: **AltStore → My Apps → "+" (top-left) → Files → iCloud Drive → Gains-unsigned.ipa**.

## Part 4 — Kill the 7-day cable ritual

11. iPhone: **AltStore → Settings → Background Refresh → ON**.
12. PC: leave AltServer running, set it to launch at Windows startup.

With the PC on and on the same WiFi, AltStore re-signs the app before it expires. No cable.

## Part 5 — Set up the app

13. Link Whoop with the Whoop email + password (expect an SMS code).
14. OpenRouter key is optional — only needed for photo logging and AI macro estimates.

---

## If something breaks

| Symptom | Fix |
|---|---|
| Error mentioning **healthkit** or **entitlement** during install | Free personal teams may not get HealthKit. Delete the `com.apple.developer.healthkit` key + `<true/>` from `Gains-Release.entitlements`, re-run the workflow, reinstall. Weight entry becomes manual. |
| "Untrusted Developer" when tapping the icon | Step 7 was skipped. |
| AltServer can't see the iPhone | Wrong iTunes/iCloud — the Microsoft Store versions do not work. Uninstall and reinstall from apple.com. |
| App won't open after about a week | Certificate expired. Open AltStore and refresh, or plug in and use AltServer. **Data is not lost.** |
| Build fails after editing code | Check the Actions log. The runner must stay `macos-26` — `macos-15` lacks the iOS 26 SDK that `Theme.swift`'s Liquid Glass code needs. |

## Known limits of the free-Apple-ID route

- Certificates last **7 days** (AltStore automates the refresh)
- **Three** sideloaded apps maximum, roughly 10 new app IDs per week
- **No lock-screen widgets** — App Groups require a paid account
- Upgrading to the $99/yr Apple Developer Program restores the widget, guarantees HealthKit, and
  extends certificates to a year

## Reminder about Whoop

The Whoop integration uses Whoop's private app API, not their official developer API. Upstream's own
warning: this is outside Whoop's developer terms and linking an account could get it rate-limited or
banned. Accepted knowingly.
