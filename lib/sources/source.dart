import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../core/cache.dart';
import '../core/models.dart';

abstract class MediaSource {
  String get id;

  /// Lists the direct subfolders and media of [path], newest media first.
  Future<Listing> list(String path);

  /// Small preview bytes, or null when the grid should decode [localFile] itself.
  Future<Uint8List?> thumbnail(MediaItem item, int size) async => null;

  /// The full file on local disk, downloading it first if needed.
  Future<File> localFile(MediaItem item);

  Future<void> close() async {}
}

/// Base for network sources: downloads go through the shared disk cache and
/// are throttled so a grid full of thumbnails doesn't open 60 connections.
abstract class RemoteSource extends MediaSource {
  final _gate = _Semaphore(4);
  final _inFlight = <String, Future<File>>{};

  /// Writes the remote file at [path] to [target].
  Future<void> download(String path, File target);

  @override
  Future<File> localFile(MediaItem item) {
    if (item.localPath != null) return Future.value(File(item.localPath!));
    final key = '$id|${item.path}|${item.modified.millisecondsSinceEpoch}|${item.size}';
    return _inFlight.putIfAbsent(key, () async {
      try {
        return await MediaCache.instance.getOrCreate(key, item.name, (target) async {
          await _gate.run(() => download(item.path, target));
        });
      } finally {
        _inFlight.remove(key);
      }
    });
  }
}

class _Semaphore {
  _Semaphore(this._slots);
  int _slots;
  final _waiters = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() task) async {
    if (_slots == 0) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    } else {
      _slots--;
    }
    try {
      return await task();
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      } else {
        _slots++;
      }
    }
  }
}
