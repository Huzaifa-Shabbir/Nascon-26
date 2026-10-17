# NaSCon Sports mobile frontend

Functional Flutter Android frontend for the Multi-Sport League & Club Operations Platform. This phase uses persistent local demonstration data. It does not call a backend, authenticate with a server, charge money, consume live server streams, or issue server-signed receipts.

## Run

Install a Flutter SDK satisfying the Dart SDK constraint in `pubspec.yaml`, Android SDK, and an Android 10+ emulator or device. Check `flutter doctor` and accept Android licenses first. From this directory (`mobile/mobile`):

```powershell
flutter pub get
flutter devices
flutter run -d <device-id>
```

For a browser layout preview when Chrome is available, use `flutter run -d chrome`. Android is the delivery target; browser secure-storage and printing behavior can differ.

## Demo accounts

All five accounts use `Nascon@26`. The sign-in screen also has an account chooser.

| Email | Role |
|---|---|
| admin@nascon.test | Platform administrator |
| organizer@nascon.test | League organizer |
| manager@nascon.test | Club manager |
| player@nascon.test | Player |
| viewer@nascon.test | Viewer |

Administrators use scoring and roster tools. Organizers score; club managers manage their roster. Players and viewers browse and shop. These are intentionally public sample credentials.

## Included flows

- Animated sports splash, validated sign-in and role-aware home.
- Searchable/filterable fixtures, match detail, event timeline and pinned merchandise.
- Standings with qualification, club profile, roster, player details and illustrative season history.
- Merchandise variants, cart quantities, mock checkout, order history and PDF receipt preview/sharing.
- Mock payment success, decline and capture failure; `WELCOME10` discount.
- Club-manager add, transfer, loan and release forms, confirmation and activity history.
- Organizer score entry and score compensation.
- Persistent pending actions, local sync results, offline status strip and future server address setting.

Club history and season statistics are illustrative. Sports configuration, scoring and sync are frontend demonstrations rather than the complete backend competition contract.

## Offline demonstration

1. Sign in as organizer or administrator. Open **Profile → Sync & offline** and enable **Demo offline mode**.
2. Browse fixtures, standings and a club profile. Queue a score from the scoring desk.
3. Sign in as manager or administrator and queue a transfer, loan or release. Registering a new player requires demo online mode.
4. Force-close and reopen the app: queued actions remain locally stored.
5. Disable **Demo offline mode**, sync any remaining pending actions, and inspect each result in the queue.

The toggle simulates connectivity; it does not detect or control Wi-Fi. Local sync updates local data. Production server conflict rules, authenticated device identities, signatures and the full §5.14 behavior remain backend-integration work.

## Persistence and integration boundary

`lib/core.dart` stores cart, orders, stock, roster, activity, match changes and pending actions as JSON using `shared_preferences`. Fixtures and profiles originate from bundled sample data. Remembered demo roles use `flutter_secure_storage`; no real JWTs are generated. Clearing app data resets the demonstration.

The preference-backed cache supports this frontend-only phase. Production offline support must move records and the outbox into SQLite/Hive, connect real authentication with Android Keystore storage, implement transactional sync and consume API WebSocket/SSE updates. Settings currently saves a server address only.

## Checks

```powershell
flutter analyze
flutter test
```

`test/app_test.dart` covers checkout/stock persistence, queue persistence and single application, scoring compensation and role access, plus screen rendering at 360×640 and 640×360. These are available checks; consult the current build report for actual execution results.

## Android release

```powershell
flutter build apk --release
New-Item -ItemType Directory -Force ../release
Copy-Item build/app/outputs/flutter-apk/app-release.apk ../release/app-release.apk
adb install -r ../release/app-release.apk
```

Flutter outputs `build/app/outputs/flutter-apk/app-release.apk`. The repository delivery path is `mobile/release/app-release.apk`. Minimum Android SDK is 29. Current release configuration uses a local debug signing key for the demo; configure dedicated signing before public distribution. These instructions do not assert that an APK has already been produced.

## Design and provenance

The user's approved theme supplies olive/lime gradients, cream surfaces, rounded controls and dimensional sports imagery. Theme tokens and shared components are maintained in `lib/core.dart`.

`assets/sports-mascot.png` and `assets/falcons-jersey.png` were generated using the built-in image tool. Exact prompts are embedded in PNG text metadata. `assets/fonts/Nunito.ttf` ships under SIL Open Font License 1.1; retain `assets/fonts/OFL.txt`. Bundled art and fonts need no runtime downloads.
