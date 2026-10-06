import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

import '../core/models.dart';
import '../sources/source.dart';

/// A video inside the viewer. The player only exists while the page is the
/// current one, so swiping past videos doesn't keep decoders alive.
///
/// Android plays through the system's ExoPlayer and Linux through the system
/// libmpv, so neither build has to bundle a video engine.
class VideoPage extends StatefulWidget {
  const VideoPage({
    super.key,
    required this.source,
    required this.item,
    required this.active,
    required this.autoplay,
  });

  final MediaSource source;
  final MediaItem item;
  final bool active;
  final bool autoplay;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  _Backend? _backend;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(VideoPage old) {
    super.didUpdateWidget(old);
    if (widget.active && _backend == null && !_loading) _start();
    if (!widget.active && _backend != null) {
      _backend!.dispose();
      setState(() => _backend = null);
    }
  }

  @override
  void dispose() {
    _backend?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = await widget.source.localFile(widget.item);
      if (!mounted || !widget.active) return;
      final backend = Platform.isAndroid ? _ExoBackend() : _MpvBackend();
      await backend.open(file, widget.autoplay);
      if (!mounted || !widget.active) {
        backend.dispose();
        return;
      }
      _backend = backend;
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Text(
          'Can\'t play ${widget.item.name}\n$_error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    final backend = _backend;
    if (backend == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: backend.view()),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ListenableBuilder(
            listenable: backend,
            builder: (_, _) => _Controls(backend),
          ),
        ),
      ],
    );
  }
}

/// The few things the controls need from a player, whichever engine it is.
abstract class _Backend extends ChangeNotifier {
  Future<void> open(File file, bool play);
  Widget view();
  bool get playing;
  Duration get position;
  Duration get duration;
  void toggle();
  void seek(Duration to);
}

class _ExoBackend extends _Backend {
  VideoPlayerController? _c;

  @override
  Future<void> open(File file, bool play) async {
    final c = VideoPlayerController.file(file);
    _c = c;
    await c.initialize();
    await c.setLooping(true);
    c.addListener(notifyListeners);
    if (play) await c.play();
  }

  @override
  Widget view() => Center(
    child: AspectRatio(
      aspectRatio: _c!.value.aspectRatio,
      child: VideoPlayer(_c!),
    ),
  );

  @override
  bool get playing => _c?.value.isPlaying ?? false;
  @override
  Duration get position => _c?.value.position ?? Duration.zero;
  @override
  Duration get duration => _c?.value.duration ?? Duration.zero;
  @override
  void toggle() => playing ? _c?.pause() : _c?.play();
  @override
  void seek(Duration to) => _c?.seekTo(to);

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }
}

class _MpvBackend extends _Backend {
  static bool _initialized = false;

  late final Player _player;
  late final VideoController _controller;
  final _subs = <StreamSubscription<Object>>[];

  @override
  Future<void> open(File file, bool play) async {
    if (!_initialized) {
      MediaKit.ensureInitialized();
      _initialized = true;
    }
    _player = Player();
    _controller = VideoController(_player);
    _subs.addAll([
      _player.stream.playing.listen((_) => notifyListeners()),
      _player.stream.position.listen((_) => notifyListeners()),
      _player.stream.duration.listen((_) => notifyListeners()),
    ]);
    await _player.setPlaylistMode(PlaylistMode.single);
    await _player.open(Media(file.path), play: play);
  }

  @override
  Widget view() => Video(controller: _controller, controls: NoVideoControls);

  @override
  bool get playing => _player.state.playing;
  @override
  Duration get position => _player.state.position;
  @override
  Duration get duration => _player.state.duration;
  @override
  void toggle() => _player.playOrPause();
  @override
  void seek(Duration to) => _player.seek(to);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}

class _Controls extends StatelessWidget {
  const _Controls(this.b);
  final _Backend b;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final max = b.duration.inMilliseconds.toDouble();
    const label = TextStyle(color: Colors.white, fontSize: 12);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 16, 4),
          child: Row(
            children: [
              IconButton(
                iconSize: 32,
                color: Colors.white,
                icon: Icon(
                  b.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                onPressed: b.toggle,
              ),
              Text(_fmt(b.position), style: label),
              Expanded(
                child: Slider(
                  value: max <= 0
                      ? 0
                      : b.position.inMilliseconds.clamp(0, max).toDouble(),
                  max: max <= 0 ? 1 : max,
                  onChanged: max <= 0
                      ? null
                      : (v) => b.seek(Duration(milliseconds: v.round())),
                ),
              ),
              Text(_fmt(b.duration), style: label),
            ],
          ),
        ),
      ),
    );
  }
}
