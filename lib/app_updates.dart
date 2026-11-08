import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Keeps the app on the newest over-the-air (Shorebird) patch.
///
/// The Shorebird engine already checks for and downloads the newest patch in
/// the background every time the app starts (`auto_update` in
/// shorebird.yaml), and the downloaded patch runs from the next launch. That
/// covers a fresh install from Google Play: the first launch downloads every
/// change shipped since that store build, and the next launch runs it.
///
/// What it does not cover is an app that stays open, or parked in the
/// background, for days: no launch, no check. This class checks again
/// whenever the app comes back to the foreground and the last check is over
/// [interval] old, downloading quietly so the next launch is current. It
/// never interrupts the member and never restarts the app.
class AppUpdates {
  AppUpdates._();
  static final instance = AppUpdates._();

  static const interval = Duration(minutes: 30);

  final ShorebirdUpdater _updater = ShorebirdUpdater();

  // The engine's own launch check counts as the first one.
  DateTime _lastCheck = DateTime.now();
  bool _busy = false;

  Future<void> checkOnResume() async {
    if (kIsWeb || _busy || !_updater.isAvailable) return;
    final now = DateTime.now();
    if (now.difference(_lastCheck) < interval) return;
    _busy = true;
    _lastCheck = now;
    try {
      if (await _updater.checkForUpdate() == UpdateStatus.outdated) {
        await _updater.update();
      }
    } catch (_) {
      // Offline, or the engine is already downloading: the next resume or
      // launch tries again.
    } finally {
      _busy = false;
    }
  }
}
