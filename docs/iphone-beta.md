# iPhone beta path

Two install routes for the five observed sessions. Neither has been run on a physical iPhone yet. Record each device run with the checklist below.

## Verified so far (Nov 14, 2026, Mac only)

- `flutter analyze`: no issues. `flutter test`: 401 passed. Unsigned release build `flutter build ios --release --no-codesign`: built `Runner.app` (20.0 MB).
- Integration test on the iPhone 17 Simulator: 8 passed (`flutter test integration_test -d <simulator id>`).
- No code-signing identity is installed on this Mac. Xcode lists Joshua's iPhone Air as paired but `unavailable` (not connected or locked).

Raw output is in `docs/evidence/iphone-beta/`.

## Route A — direct install from Xcode (free Apple ID, for the tester sessions on your own phone)

Use this to put the app on your own iPhone Air and run the five sessions on that phone. Testers use your phone, so nothing gets installed on theirs.

1. In Xcode → Settings → Accounts, add your Apple ID. A free personal team is fine.
2. Open `app/ios/Runner.xcworkspace`, select the Runner target → Signing & Capabilities → check *Automatically manage signing* and pick your personal team. If `com.jmbugarin.classmap` is taken, change the bundle id to something unique (for example add `.beta`).
3. On the iPhone: Settings → Privacy & Security → Developer Mode → on (restart required). Connect with USB and trust the Mac.
4. Build and install from `app/`:
   ```
   flutter pub get
   flutter devices                         # note the iPhone id
   flutter run --release -d <iphone id>    # optional: --dart-define-from-file=dart_defines.json
   ```
5. On first launch, trust the developer profile: Settings → General → VPN & Device Management.

With a free team the provisioning profile expires after 7 days, so reinstall before each session batch. Record the git SHA you built from (`git rev-parse HEAD`).

## Route B — TestFlight (needed only if testers install on their own phones)

This needs the paid Apple Developer Program, which is an external gate. Once enrolled: create the app record in App Store Connect with the bundle id, then `flutter build ipa --release`, upload the `.ipa` with Xcode Organizer or Transporter, add internal testers (up to 100, no review) or external testers (needs Beta App Review), and send the TestFlight link.

## Before inviting anyone

- **Map tiles.** Without a key the app uses OpenStreetMap's public tile server, which the OSM tile policy doesn't allow for distributed apps. That's acceptable for a few sessions on one phone. For TestFlight, set `TILE_PROVIDER`/`TILE_KEY` (see `app/README.md`) or keep sessions on your phone.
- **Schedules.** Use the synthetic checklist schedule below. Don't collect real schedules.

## Device checklist (fill one per device run)

| Field | Value |
|---|---|
| Date / build SHA / install route | |
| Device / iOS version | |
| Fresh install opens on the map | pass / fail |
| Room search (e.g. "PHYS 2", "baskin 101", a typo) | |
| Paste import of the synthetic schedule | |
| Calendar (.ics) import | |
| Malformed paste is rejected with a message | |
| Location permission denied → app still usable | |
| Airplane mode, cold restart → schedule and rooms still work | |
| Persisted schedule after force quit | |
| Walk there opens Apple Maps to the right door | |
| Notification permission + one reminder delivered | |
| Interrupt (call/app switch) and resume | |
| Photo import on a printed synthetic schedule | |
| Issues (redacted) | |

Synthetic schedule for paste import:

```
CSE 101 - 01  LEC  MWF 9:20AM-10:25AM  Baskin Auditorium 101
MATH 19B - 01 LEC  TuTh 11:40AM-1:15PM  Physical Sciences 110
WRIT 2 - 05   SEM  TuTh 3:20PM-4:55PM  Humanities 1 202
```
