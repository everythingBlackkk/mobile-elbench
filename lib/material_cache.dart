import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One cached material file as the eviction policy sees it.
class CachedMaterial {
  const CachedMaterial({
    required this.name,
    required this.size,
    required this.lastOpened,
    required this.opens,
  });
  final String name;
  final int size;
  final DateTime lastOpened;
  final int opens;
}

/// Decides which cached study materials to delete.
///
/// It is a two-tier LRU: materials opened at least [frequentOpens] times
/// within [frequentWindow] are "frequent"; everything else is "occasional".
/// When space is needed, occasional files go first (least recently opened
/// first), then frequent ones. A burst of one-off PDFs therefore cannot push
/// out the files a student keeps coming back to, while files nobody opened
/// for [staleAfter] are removed even when there is room. Files opened in the
/// last [inUseWindow] (the one on screen) are never removed.
class MaterialCachePolicy {
  const MaterialCachePolicy({
    this.limitBytes = 400 * 1024 * 1024,
    this.targetBytes = 320 * 1024 * 1024,
    this.frequentOpens = 2,
    this.frequentWindow = const Duration(days: 14),
    this.staleAfter = const Duration(days: 30),
    this.inUseWindow = const Duration(minutes: 10),
  });

  /// The cache never grows past this, counting the file being downloaded.
  final int limitBytes;

  /// Once over the limit, trimming goes down to this, so it does not run
  /// again on the very next download.
  final int targetBytes;
  final int frequentOpens;
  final Duration frequentWindow, staleAfter, inUseWindow;

  bool isFrequent(CachedMaterial file, DateTime now) =>
      file.opens >= frequentOpens &&
      now.difference(file.lastOpened) <= frequentWindow;

  /// Names to delete so [incomingBytes] more fit within the limit.
  List<String> evictions(
    List<CachedMaterial> files, {
    required DateTime now,
    int incomingBytes = 0,
    Set<String> keep = const {},
  }) {
    bool protected(CachedMaterial f) =>
        keep.contains(f.name) || now.difference(f.lastOpened) < inUseWindow;
    final remove = <String>[];
    final remaining = <CachedMaterial>[];
    for (final file in files) {
      if (!protected(file) && now.difference(file.lastOpened) > staleAfter) {
        remove.add(file.name);
      } else {
        remaining.add(file);
      }
    }
    var total = remaining.fold<int>(0, (sum, f) => sum + f.size);
    if (total + incomingBytes <= limitBytes) return remove;
    final candidates = remaining.where((f) => !protected(f)).toList()
      ..sort((a, b) {
        final tier = (isFrequent(a, now) ? 1 : 0).compareTo(
          isFrequent(b, now) ? 1 : 0,
        );
        return tier != 0 ? tier : a.lastOpened.compareTo(b.lastOpened);
      });
    for (final file in candidates) {
      if (total + incomingBytes <= targetBytes) break;
      remove.add(file.name);
      total -= file.size;
    }
    return remove;
  }
}

/// How often and how recently each cached file was opened, kept next to the
/// files in a small JSON index. A missing or damaged index only means files
/// count as opened once, at their file time.
class MaterialCacheIndex {
  MaterialCacheIndex(this.directory);
  final Directory directory;
  Map<String, (int, int)>? _entries;
  Future<void> _queue = Future.value();

  File get _file => File('${directory.path}/index.json');

  /// Runs index work one step at a time.
  Future<T> _locked<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, (int, int)>> _load() async {
    final loaded = _entries;
    if (loaded != null) return loaded;
    final entries = <String, (int, int)>{};
    try {
      final data = jsonDecode(await _file.readAsString());
      if (data is Map) {
        data.forEach((name, value) {
          if (name is String && value is Map) {
            final opens = value['o'], time = value['t'];
            if (opens is int && time is int) entries[name] = (opens, time);
          }
        });
      }
    } catch (_) {}
    return _entries = entries;
  }

  Future<void> _save() async {
    final entries = _entries ?? {};
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        for (final e in entries.entries)
          e.key: {'o': e.value.$1, 't': e.value.$2},
      }),
    );
    await tmp.rename(_file.path);
  }

  /// Records that [name] was opened now.
  Future<void> opened(String name, DateTime now) => _locked(() async {
    final entries = await _load();
    final previous = entries[name];
    entries[name] = ((previous?.$1 ?? 0) + 1, now.millisecondsSinceEpoch);
    await _save();
  });

  /// Every cached material file, with its open history.
  Future<List<CachedMaterial>> files() => _locked(() async {
    final entries = await _load();
    final files = <CachedMaterial>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name.startsWith('index.json') || name.endsWith('.part')) continue;
      final stat = await entity.stat();
      final known = entries[name];
      files.add(
        CachedMaterial(
          name: name,
          size: stat.size,
          lastOpened: known == null
              ? stat.modified
              : DateTime.fromMillisecondsSinceEpoch(known.$2),
          opens: known?.$1 ?? 1,
        ),
      );
    }
    return files;
  });

  /// Deletes [names] and forgets them.
  Future<void> remove(Iterable<String> names) => _locked(() async {
    final entries = await _load();
    for (final name in names) {
      entries.remove(name);
      try {
        await File('${directory.path}/$name').delete();
      } catch (_) {}
    }
    // Forget files Android removed on its own to free space.
    final present = <String>{
      await for (final e in directory.list())
        if (e is File) e.uri.pathSegments.last,
    };
    entries.removeWhere((name, _) => !present.contains(name));
    await _save();
  });

  /// Deletes partial downloads that are not in progress.
  Future<void> removePartials(Set<String> active) => _locked(() async {
    await for (final entity in directory.list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is File && name.endsWith('.part') && !active.contains(name)) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  });
}
