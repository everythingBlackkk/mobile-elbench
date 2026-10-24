import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';

// Top-level so they can run on a background isolate without capturing state.
String _encode(Map<String, dynamic> value) => jsonEncode(value);
Object? _decode(String raw) => jsonDecode(raw);

/// Keeps the last sanitized Home and Profile documents on disk, so a cold
/// start shows the signed-in viewer's content immediately and revalidates it
/// in the background. Entries belong to one viewer and locale and are
/// removed on sign-out or session expiry.
class PageStore {
  PageStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static const persistedPaths = {'/community', '/profile'};
  static const maxAge = Duration(days: 3);

  final Future<Directory> Function() _directory;
  Timer? _debounce;
  Map<String, dynamic>? _pending;
  Future<void>? _flushing;
  int _generation = 0;

  Future<File> _file() async =>
      File('${(await _directory()).path}/elbench-pages.json');

  /// Returns {viewer, locale, pages: {key: {envelope, fetchedAt}}} or null.
  Future<Map<String, dynamic>?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      // Decoding a long feed must not hold up the launch frame.
      final decoded = raw.length < 16 * 1024
          ? jsonDecode(raw)
          : await compute(_decode, raw);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        return null;
      }
      final saved = DateTime.fromMillisecondsSinceEpoch(
        decoded['savedAt'] is int ? decoded['savedAt'] as int : 0,
      );
      if (DateTime.now().difference(saved) > maxAge) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  /// Debounced write of the current documents for [viewer].
  void write(
    String viewer,
    String locale,
    Map<String, ({Map<String, dynamic> envelope, DateTime fetchedAt})> pages,
  ) {
    _pending = {
      'version': 1,
      'viewer': viewer,
      'locale': locale,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'pages': {
        for (final entry in pages.entries)
          entry.key: {
            'envelope': entry.value.envelope,
            'fetchedAt': entry.value.fetchedAt.millisecondsSinceEpoch,
          },
      },
    };
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), flush);
  }

  Future<void> flush() async {
    _debounce?.cancel();
    final pending = _pending;
    _pending = null;
    if (pending == null) return;
    final generation = _generation;
    final previous = _flushing;
    final task = () async {
      await previous;
      try {
        final text = await compute(_encode, pending);
        // Signed out meanwhile: never recreate the previous viewer's file.
        if (generation != _generation) return;
        final file = await _file();
        final temporary = File('${file.path}.part');
        await temporary.writeAsString(text, flush: true);
        if (generation != _generation) {
          await temporary.delete();
          return;
        }
        await temporary.rename(file.path);
      } catch (_) {}
    }();
    _flushing = task;
    await task;
  }

  Future<void> clear() async {
    _generation++;
    _debounce?.cancel();
    _pending = null;
    await _flushing;
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
