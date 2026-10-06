import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/video_frames.dart';
import '../sources/source.dart';

/// The grid's (cached) preview for [item]; the viewer shows it while the full
/// image decodes, instead of a black frame.
Future<ImageProvider?> thumbnailProvider(
  MediaSource source,
  MediaItem item,
  int size,
) => _ThumbCache.request(source, item, size).future;

/// A pending thumbnail. [cancel] drops it if it hasn't started yet, so cells
/// scrolled past don't hold up the ones on screen.
class _Ticket {
  _Ticket(this.future, [this.cancel = _noop]);
  final Future<ImageProvider?> future;
  final void Function() cancel;
  static void _noop() {}
}

class _Job {
  _Job(this.key, this.run);
  final String key;
  final Future<ImageProvider?> Function() run;
  final done = Completer<ImageProvider?>();
  int holders = 0;
}

/// Resolves and decodes thumbnails a few at a time, remembering recent ones so
/// scrolling back doesn't re-download or re-request them.
class _ThumbCache {
  static final _map = <String, Future<ImageProvider?>>{};
  static const _max = 600;
  static final _waiting = <String, _Job>{};
  static int _running = 0;
  static const _parallel = 6;

  static _Ticket request(MediaSource source, MediaItem item, int size) {
    final key = '${source.id}|${item.path}|$size';
    final hit = _map.remove(key);
    if (hit != null) return _Ticket(_map[key] = hit);
    final job = _waiting.putIfAbsent(
      key,
      () => _Job(key, () => _resolve(source, item, size)),
    );
    job.holders++;
    _pump();
    var cancelled = false;
    return _Ticket(job.done.future, () {
      if (cancelled) return;
      cancelled = true;
      if (--job.holders == 0) _waiting.remove(key);
    });
  }

  static void _pump() {
    while (_running < _parallel && _waiting.isNotEmpty) {
      final job = _waiting.remove(_waiting.keys.first)!;
      _running++;
      final f = job.run();
      _map[job.key] = f;
      if (_map.length > _max) _map.remove(_map.keys.first);
      f
          .then(
            job.done.complete,
            onError: (Object e, StackTrace st) {
              // Failures shouldn't stick: let the next build retry.
              _map.remove(job.key);
              job.done.completeError(e, st);
            },
          )
          .whenComplete(() {
            _running--;
            _pump();
          });
    }
  }

  static Future<ImageProvider?> _resolve(
    MediaSource source,
    MediaItem item,
    int size,
  ) async {
    final provider = await _provider(source, item, size);
    // Decoding counts towards the limit too, so a fast scroll doesn't leave a
    // backlog of decodes for cells that are gone.
    if (provider != null) await _decode(provider);
    return provider;
  }

  static Future<ImageProvider?> _provider(
    MediaSource source,
    MediaItem item,
    int size,
  ) async {
    if (item.localPath != null && !item.isVideo) {
      return _resized(FileImage(File(item.localPath!)), size);
    }
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
    return _resized(FileImage(await source.localFile(item)), size);
  }

  static ImageProvider _resized(ImageProvider p, int size) =>
      ResizeImage(p, width: size, policy: ResizeImagePolicy.fit);

  static Future<void> _decode(ImageProvider provider) {
    final done = Completer<void>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(listener);
      },
      onError: (Object e, StackTrace? st) {
        if (!done.isCompleted) done.completeError(e, st);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return done.future;
  }
}

class MediaThumb extends StatefulWidget {
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
  State<MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<MediaThumb> {
  late _Ticket _ticket = _request();

  _Ticket _request() =>
      _ThumbCache.request(widget.source, widget.item, widget.size);

  @override
  void didUpdateWidget(MediaThumb old) {
    super.didUpdateWidget(old);
    if (old.source.id != widget.source.id ||
        old.item.path != widget.item.path ||
        old.size != widget.size) {
      _ticket.cancel();
      _ticket = _request();
    }
  }

  @override
  void dispose() {
    _ticket.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(color: scheme.surfaceContainerHighest);

    final image = FutureBuilder<ImageProvider?>(
      future: _ticket.future,
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
              widget.item.name,
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
