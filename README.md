# ElBench mobile (Flutter)

Native Android and iOS client for [elbench.com](https://elbench.com). It replaces
the earlier Android WebView app and keeps its Google Play listing.

| Platform | Identifier          |
|----------|---------------------|
| Android  | `com.sahbakwebview` |
| iOS      | `com.sahbak.ios`    |

Version: `pubspec.yaml` (`2.5.3+15`). The Android version code must stay above
the last published WebView build (5).

## Requirements

- Flutter 3.44.2 (Dart 3.12.2), pinned in `.fvmrc`
- Xcode with an Apple Developer team (the project uses automatic signing, team `VV9D87Q44W`)
- Android SDK 37 and NDK 28.2.13676358
- The Laravel backend with the native mobile API (`/mobile/session`, `/push/mobile`)

## Backend

Release builds use `https://elbench.com`. Each screen requests the website's
own routes with `X-ElBench-Mobile: 1`. The server's `NativeMobileResponse`
middleware returns sanitized JSON instead of HTML. Session cookies are kept in
the platform keychain/keystore (`flutter_secure_storage`). Passwords are
never stored.

To point a development build at another server:

```sh
flutter run --dart-define=API_BASE_URL=https://staging.example.com
```

Only HTTPS is accepted, except for loopback and private LAN addresses.

## Domain

The site moved from `sahbak.site` to `elbench.com` in October 2026 (2.0.1).
`sahbak.site` now redirects to `elbench.com` (Cloudflare, 308). The app treats
links that still name `sahbak.site`, `www.sahbak.site` or `www.elbench.com`
as in-app links and loads their images from `elbench.com`. A sign-in saved by
an older build is carried over on first launch, so users stay signed in.

## Behaviour

- **Pull to refresh:** every screen reloads its content and the notification
  and inbox badges. Other open screens are marked stale and refetch when shown.
  A subtle haptic confirms when a pull triggers a refresh. Schedule uses the same
  platform-adaptive spinner as the other pages and keeps the selected day.
  Returning to the app refreshes the badges; after 2+ minutes in the background
  the visible screen reloads too.
- **Study materials:** each community has a Materials page. PDFs open inside
  the app (`pdfx`, the platform's own PDF renderer) and images in a zoomable
  viewer; both are downloaded once through a short-lived signed link and kept
  in the app's private cache (up to 400 MB, cleared on sign-out). Text, Word
  (DOCX) and Excel (XLSX) files show the server's preview. **Download** saves
  the file through the system's save dialog (`flutter_file_dialog`), so no
  storage permission is needed. Community admins can upload and delete files
  and send notifications to a subject's followers.
- **Subjects:** Home › Edit subjects chooses which communities appear on Home
  and send notifications, from either level.
- **Infinite scrolling:** the home feed, post comments, community questions,
  answers and profile activity load the next page as you approach the end,
  showing skeleton cards while it loads. Rows survive reactions and other
  actions; pull to refresh starts again from the top.

## Performance

- **Instant navigation:** tapping a post or community question renders it
  immediately from the row already on screen; comments/answers stream in when
  the full document arrives. Uncached screens slide in at once with skeleton
  placeholders instead of freezing on the previous screen during the request.
- **Caching:** up to 32 screens are kept for 30 minutes and shown instantly,
  then revalidated in the background (stale-while-revalidate). A screen
  fetched less than 20 s ago is reused without a request. Writes mark cached
  screens stale instead of discarding them. Home and Profile are persisted to
  disk per viewer, so a cold start shows them at once; Home is requested in
  parallel with the session check.
- **Fewer requests:** concurrent requests for the same screen are shared, a
  post is prefetched on touch-down, Profile is prefetched once after Home, and
  reactions update the row in place instead of reloading the page.
- **Network and images:** HTTPS connections are kept alive for 90 s (a new
  TLS handshake to the server costs ~0.2 s). Images use a 7-day disk cache
  (`lib/image_cache.dart`) and decode at display size.
- **Rendering:** comment lists build lazily, and persisted JSON is encoded and
  decoded off the UI thread.
- **Scrolling:** flings carry about 30% further on iOS and 15% on Android
  (`lib/scroll_physics.dart`) while keeping each platform's native bounce or
  stretch, and the Home feed builds about a screen ahead so fast flings reach
  ready posts with their photos already loading.

Measured on an iPhone 11 (profile mode, 450 ms simulated server latency):
opening a post went from 500 ms to 23 ms to first content, the first Profile
visit from 501 ms to 66 ms, and the workload's API requests from 18 to 10.

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

### Over-the-air updates (Shorebird)

Store builds go through Shorebird, so later UI and logic changes reach phones without a new store version.
One-time setup: `shorebird login`, then `shorebird init` (adds the public `shorebird.yaml`).

```sh
./shorebird.sh release android   # upload build/app/outputs/bundle/release/app-release.aab to Google Play
./shorebird.sh release ios       # upload build/ios/ipa/*.ipa to App Store Connect
./shorebird.sh patch android     # after changing Dart code; phones get it on their next launch
./shorebird.sh patch ios
```

A patch can change any Dart code: every screen, layout, colour, text and behaviour. It cannot change Swift/Kotlin,
native plugins, `Info.plist`/`AndroidManifest.xml` or files in `assets/`. Those need a new store release; Shorebird
warns before uploading such a patch. Images a patch needs must come from the server. The iOS liquid-glass surface
is native; a patch can set `nativeGlassEnabled` in `lib/native_glass.dart` to `false` to draw it in Flutter instead.
Releases keep all Material icons (`--no-tree-shake-icons`), so patches can use any of them. Patches are signed:
releases embed `~/Documents/secret-app/shorebird/public.pem` and accept only patches signed with the matching
`private.pem`, which stays on the release Mac (never commit it). Patched code runs in an
interpreter on iOS, and patches are tested on a real device (`./shorebird.sh preview`), not the simulator.

### Push notifications

Android and iOS use the same Firebase project, `elbench-624b9`, which the server also sends through. The config files (`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`) are not in this repository.

iOS push is off by default because Apple only allows it for apps signed by a paid Apple Developer Program team. To turn it on:

1. Create an APNs key (Apple Developer → Keys) and upload it in Firebase → Project settings → Cloud Messaging → Apple app `com.sahbak.ios`.
2. Add `ios/Runner/GoogleService-Info.plist` for `com.sahbak.ios` from Firebase.
3. In `ios/Flutter/Push.xcconfig`, set `ELBENCH_PUSH = Push`. This signs the app with the `aps-environment` entitlement and makes the app register for notifications.
4. Enable Push Notifications for the App ID `com.sahbak.ios` and sign with your paid team.

Android push works with `google-services.json`.
