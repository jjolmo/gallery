import 'dart:io';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/video_frames.dart';
import '../sources/source.dart';

/// Resolves the provider for a grid cell, remembering recent ones so scrolling
/// back doesn't re-download or re-request thumbnails.
class _ThumbCache {
  static final _map = <String, Future<ImageProvider?>>{};
  static const _max = 600;

  static Future<ImageProvider?> get(
    MediaSource source,
    MediaItem item,
    int size,
  ) {
    final key = '${source.id}|${item.path}|$size';
    final hit = _map.remove(key);
    if (hit != null) return _map[key] = hit;
    final f = _resolve(source, item, size);
    _map[key] = f;
    if (_map.length > _max) _map.remove(_map.keys.first);
    // Failures shouldn't stick: let the next build retry.
    f.catchError((_) {
      _map.remove(key);
      return null;
    });
    return f;
  }

  static Future<ImageProvider?> _resolve(
    MediaSource source,
    MediaItem item,
    int size,
  ) async {
    final bytes = await source.thumbnail(item, size);
    if (bytes != null) return MemoryImage(bytes);
    if (item.isVideo) {
      final frame = await VideoFrames.instance.frame(
        '${source.id}|${item.path}|${item.modified.millisecondsSinceEpoch}',
        () => source.videoInput(item),
        size,
      );
      return frame == null ? null : MemoryImage(frame);
    }
    final file = await source.localFile(item);
    return ResizeImage(
      FileImage(file),
      width: size,
      policy: ResizeImagePolicy.fit,
    );
  }
}

class MediaThumb extends StatelessWidget {
  const MediaThumb({
    super.key,
    required this.source,
    required this.item,
    required this.size,
  });

  final MediaSource source;
  final MediaItem item;
  final int size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(color: scheme.surfaceContainerHighest);

    Widget image;
    if (item.localPath != null && !item.isVideo) {
      image = Image(
        image: ResizeImage(
          FileImage(File(item.localPath!)),
          width: size,
          policy: ResizeImagePolicy.fit,
        ),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _broken(scheme),
      );
    } else {
      image = FutureBuilder<ImageProvider?>(
        future: _ThumbCache.get(source, item, size),
        builder: (context, snap) {
          if (snap.hasError) return _broken(scheme);
          if (snap.connectionState != ConnectionState.done) return placeholder;
          final provider = snap.data;
          if (provider == null) return _videoPlaceholder(scheme);
          return Image(
            image: provider,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _broken(scheme),
          );
        },
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        placeholder,
        image,
        if (item.kind != MediaKind.image)
          Positioned(right: 4, bottom: 4, child: _Badge(item.kind)),
      ],
    );
  }

  Widget _broken(ColorScheme s) => ColoredBox(
    color: s.surfaceContainerHighest,
    child: Icon(Icons.broken_image_outlined, color: s.onSurfaceVariant),
  );

  Widget _videoPlaceholder(ColorScheme s) => ColoredBox(
    color: s.surfaceContainerHigh,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined, color: s.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: s.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.kind);
  final MediaKind kind;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: kind == MediaKind.video
            ? const Icon(
                Icons.play_arrow_rounded,
                size: 16,
                color: Colors.white,
              )
            : const Text(
                'GIF',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
