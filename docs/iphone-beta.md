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
2. Put `DEVELOPMENT_TEAM = YOUR_TEAM_ID` in `app/ios/Flutter/LocalSigning.xcconfig` (git-ignored). Open `app/ios/Runner.xcworkspace` and check the resolved team under Runner → Signing & Capabilities. If `com.jmbugarin.classmap` is taken, change the bundle id to something unique (for example add `.beta`).
3. On the iPhone: Settings → Privacy & Security → Developer Mode → on (restart required). Connect with USB and trust the Mac.
4. Build and install from `app/`:
   ```
   flutter pub get
   flutter devices                         # note the iPhone id
   flutter run --release -d <iphone id>    # optional: --dart-define-from-file=dart_defines.json
   ```
5. On first launch, trust the developer profile: Settings → General → VPN & Device Management.

With a free team the provisioning profile expires after 7 days, so reinstall before each session batch. Record the git SHA you built from (`git rev-parse HEAD`).

## Route B — TestFlight (chosen for O02, so students install on their own phones)

Needs the paid Apple Developer Program ($99/year). Only Joshua can enroll. Everything else is ready in the repo.

1. Enroll at developer.apple.com. Then in App Store Connect create the app with bundle id `com.jmbugarin.classmap` (or the one used for signing) and set the paid team ID in the same local signing file.
2. Make `app/dart_defines.json` from the example. Set `TILE_PROVIDER`/`TILE_KEY` to a hosted tile provider, because OSM's public server isn't allowed for distributed apps. Set `ACTIVITY_URL` to the classmap-transit public ingress (`https://<host>/v1/activity`; see its docs/operations.md "Public ingress", which is opened only at this step).
3. Build with `flutter build ipa --release --build-number <n> --dart-define-from-file=dart_defines.json`, then upload `build/ios/ipa/*.ipa` with Transporter or `xcrun altool`.
4. Export compliance is answered in Info.plist (`ITSAppUsesNonExemptEncryption = false`; the app only uses HTTPS).
5. App Privacy answers in App Store Connect: *Data collected:* **Product Interaction** and **Device ID**, both **not linked** to the user, **not used for tracking**, purpose **Analytics**. Nothing else is collected. Schedules and pictures stay on the phone.
6. TestFlight: add students as external testers through a public link. The first external build needs Beta App Review, usually about a day. Builds expire after 90 days.
7. Before sharing the link, install the build on your own phone, turn on "Count my weekly use", find a room, and exclude your install id on the host (`transit activity-exclude <uuid>`; Settings shows the first 8 characters, and the full id is in the `activity` table for that week). Uninstall the Route A build first if the bundle ids match.

Recording O02: each consenting student reads their participant code from Settings to Joshua, who keeps it in a private cohort file, never in git. Weekly counts come from `transit activity-report cohort.txt` on finished weeks. Report the cohort count as students, and active installs only as an upper bound.

## Before inviting anyone

- **Map tiles.** Without a key the app uses OpenStreetMap's public tile server, which the OSM tile policy doesn't allow for distributed apps. That's acceptable for a few sessions on one phone. For TestFlight, set `TILE_PROVIDER`/`TILE_KEY` (see `app/README.md`).
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
