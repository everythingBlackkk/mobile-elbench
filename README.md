# ElBench mobile (Flutter)

Native Android and iOS client for [sahbak.site](https://sahbak.site). It replaces
the earlier Android WebView app and keeps its Google Play listing.

| Platform | Identifier          |
|----------|---------------------|
| Android  | `com.sahbakwebview` |
| iOS      | `com.sahbak.ios`    |

Version: `pubspec.yaml` (`2.0.0+6`). The Android version code must stay above
the last published WebView build (5).

## Requirements

- Flutter 3.44.2 (Dart 3.12.2), pinned in `.fvmrc`
- Xcode with an Apple Developer team (the project uses automatic signing, team `VV9D87Q44W`)
- Android SDK 37 and NDK 28.2.13676358
- The Laravel backend with the native mobile API (`/mobile/session`, `/push/mobile`)

## Backend

Release builds use `https://sahbak.site`. Each screen requests the website's
own routes with `X-ElBench-Mobile: 1`. The server's `NativeMobileResponse`
middleware returns sanitized JSON instead of HTML. Session cookies are kept in
the platform keychain/keystore (`flutter_secure_storage`). Passwords are
never stored.

To point a development build at another server:

```sh
flutter run --dart-define=API_BASE_URL=https://staging.example.com
```

Only HTTPS is accepted, except for loopback and private LAN addresses.

## Behaviour

- **Pull to refresh:** every screen reloads its content and the notification
  and inbox badges. Other open screens are marked stale and refetch when shown.
  Returning to the app refreshes the badges; after 2+ minutes in the background
  the visible screen reloads too.
- **Infinite scrolling:** the home feed, post comments, community questions,
  answers and profile activity load the next page as you approach the end,
  showing skeleton cards while it loads. Rows survive reactions and other
  actions; pull to refresh starts again from the top.

## Secrets (never committed)

These files are git-ignored and must be supplied locally:

| File | Purpose |
|------|---------|
| `android/key.properties` | Upload keystore path, alias and passwords |
| upload keystore (`.jks`) | Android release signing |
| `android/app/google-services.json` | Firebase (Android push) |
| `ios/Runner/GoogleService-Info.plist` | Firebase (iOS push, optional) |

`android/key.properties` format:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=elbench
keyPassword=...
```

Without `key.properties`, release builds are left unsigned and cannot be
uploaded by mistake.

## Store builds

```sh
flutter pub get
# Google Play (App Bundle)
flutter build appbundle --release
# App Store (archive, then upload with Xcode Organizer or Transporter)
flutter build ipa --release
```

Outputs:
- `build/app/outputs/bundle/release/app-release.aab`
- `build/ios/ipa/`

### iOS push notifications

iOS push is off by default. To enable it:

1. Register `com.sahbak.ios` in the Firebase project.
2. Upload an APNs key in Firebase.
3. Add `ios/Runner/GoogleService-Info.plist`.
4. Add the Push Notifications capability (`aps-environment`) to the Runner target.
5. Build with `--dart-define=IOS_PUSH_ENABLED=true`.

Android push works with `google-services.json`.
