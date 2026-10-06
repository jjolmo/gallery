import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where to read a video from: a local file, or a URL plus request headers.
class VideoInput {
  VideoInput.file(this.source) : headers = const {};
  VideoInput.url(this.source, [this.headers = const {}]);

  final String source;
  final Map<String, String> headers;
}

/// Thumbnails for videos, from a frame about a second in. Android uses the
/// system's MediaMetadataRetriever; Linux uses ffmpegthumbnailer or ffmpeg if
/// one is installed. Frames are cached on disk.
class VideoFrames {
  VideoFrames._();
  static final instance = VideoFrames._();

  static const _channel = MethodChannel('gallery/video_frame');
  final _inFlight = <String, Future<Uint8List?>>{};
  Directory? _dir;
  Future<String?>? _linuxTool;
  int _running = 0;
  final _queue = <Completer<void>>[];

  /// [key] must change when the video does (path plus modification time).
  Future<Uint8List?> frame(
    String key,
    Future<VideoInput?> Function() input,
    int size,
  ) {
    return _inFlight.putIfAbsent('$key|$size', () async {
      try {
        final file = File(
          p.join((await _cacheDir()).path, '${_hash('$key|$size')}.jpg'),
        );
        if (await file.exists()) return await file.readAsBytes();
        final bytes = await _limited(() async {
          final source = await input();
          return source == null ? null : _extract(source, size);
        });
        if (bytes != null && bytes.isNotEmpty) await file.writeAsBytes(bytes);
        return bytes;
      } catch (_) {
        return null;
      } finally {
        _inFlight.remove('$key|$size');
      }
    });
  }

  Future<Uint8List?> _extract(VideoInput input, int size) async {
    if (Platform.isAndroid) {
      return _channel.invokeMethod<Uint8List>('frame', {
        'source': input.source,
        'headers': input.headers,
        'size': size,
      });
    }
    final tool = await (_linuxTool ??= _findLinuxTool());
    if (tool == null) return null;
    return tool == 'ffmpegthumbnailer'
        ? _run('ffmpegthumbnailer', [
            '-i',
            input.source,
            '-o',
            '-',
            '-c',
            'jpeg',
            '-s',
            '$size',
            '-t',
            '10%',
          ])
        : _run('ffmpeg', [
            '-v',
            'error',
            for (final h in input.headers.entries) ...[
              '-headers',
              '${h.key}: ${h.value}\r\n',
            ],
            '-ss',
            '1',
            '-i',
            input.source,
            '-frames:v',
            '1',
            '-vf',
            "scale='min($size,iw)':-2",
            '-f',
            'image2',
            '-c:v',
            'mjpeg',
            'pipe:1',
          ]);
  }

  Future<Uint8List?> _run(String exe, List<String> args) async {
    final r = await Process.run(
      exe,
      args,
      stdoutEncoding: null,
    ).timeout(const Duration(seconds: 20));
    final out = r.stdout as List<int>;
    return r.exitCode == 0 && out.isNotEmpty ? Uint8List.fromList(out) : null;
  }

  Future<String?> _findLinuxTool() async {
    for (final tool in ['ffmpegthumbnailer', 'ffmpeg']) {
      final r = await Process.run('which', [tool]);
      if (r.exitCode == 0) return tool;
    }
    return null;
  }

  // Two at a time: decoding many videos at once stalls the grid.
  Future<T> _limited<T>(Future<T> Function() task) async {
    if (_running >= 2) {
      final turn = Completer<void>();
      _queue.add(turn);
      await turn.future;
    }
    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_queue.isNotEmpty) _queue.removeAt(0).complete();
    }
  }

  Future<Directory> _cacheDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationCacheDirectory();
    return _dir = await Directory(p.join(base.path, 'video_frames'))
        .create(recursive: true);
  }

  static String _hash(String s) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(s)) {
      h ^= b;
      h *= 0x100000001b3;
    }
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }
}
