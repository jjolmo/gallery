import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Disk cache for files fetched from remote sources.
class MediaCache {
  MediaCache._();
  static final instance = MediaCache._();

  Directory? _dir;

  Future<Directory> get dir async {
    if (_dir != null) return _dir!;
    final base = await getApplicationCacheDirectory();
    _dir = await Directory(p.join(base.path, 'remote')).create(recursive: true);
    return _dir!;
  }

  Future<File> getOrCreate(
    String key,
    String name,
    Future<void> Function(File target) fill,
  ) async {
    final d = await dir;
    // Keep the extension: the image and video decoders sniff by it.
    final file = File(
      p.join(d.path, '${_fnv1a(key)}${p.extension(name).toLowerCase()}'),
    );
    if (await file.exists() && await file.length() > 0) return file;

    final part = File('${file.path}.part');
    try {
      await fill(part);
      return await part.rename(file.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  static String _fnv1a(String s) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(s)) {
      h ^= b;
      h *= 0x100000001b3;
    }
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }

  Future<int> sizeBytes() async {
    var total = 0;
    await for (final e in (await dir).list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> clear() async {
    final d = await dir;
    await d.delete(recursive: true);
    _dir = null;
  }
}
