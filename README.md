# Last version v4.5.0

Use **Flutter 3.44.2** with **Dart 3.12.2**, as pinned in `.fvmrc`.
iOS uses the standard Flutter SDK with **no Shorebird**. Shorebird is for Android only.

## Build an IPA for App Store upload

You need macOS, a compatible current Xcode with its command-line tools, CocoaPods,
and a paid Apple Developer Program team with distribution signing access.
Create an App Store Connect app record with bundle ID `com.sahbak.ios`.

1. Make sure `flutter` points to the standard Flutter 3.44.2 SDK, then run these
   commands from this directory:

   ```sh
   flutter --version
   flutter pub get
   open ios/Runner.xcworkspace
   ```

2. In Xcode, select the **Runner** target and open **Signing & Capabilities**.
   Keep **Automatically manage signing** enabled, select your paid distribution
   team for the Release configuration, and confirm the bundle identifier is
   `com.sahbak.ios`. Replace the existing local signing team with your team.

3. Build and export the signed IPA:

   ```sh
   flutter build ipa --release --no-tree-shake-icons --export-method app-store
   ```

   Outputs:

   - IPA: `build/ios/ipa/*.ipa`
   - Xcode archive: `build/ios/archive/Runner.xcarchive`

4. Upload the IPA with Apple's **Transporter** app using your App Store Connect
   account. Alternatively, open the archive in Xcode Organizer and choose
   **Distribute App → App Store Connect → Upload**. After processing, select the
   build in App Store Connect for TestFlight or App Store submission.

See the [Flutter iOS deployment guide](https://docs.flutter.dev/deployment/ios)
and [Apple's build upload guide](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds).
