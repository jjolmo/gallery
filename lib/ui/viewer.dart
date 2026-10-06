import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../sources/source.dart';
import 'video_page.dart';

/// Full-screen viewer.
///
/// Tap the left or right band, or swipe sideways, to change item. Tap the
/// center band or swipe up/down to close. Pinch or double-tap to zoom.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.source,
    required this.items,
    required this.initialIndex,
  });

  final MediaSource source;
  final List<MediaItem> items;
  final int initialIndex;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> with SingleTickerProviderStateMixin {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _zoomed = false;
  final _focus = FocusNode();

  double _dragDy = 0;
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() => _dragDy = _settleFrom * (1 - _settle.value)));
  double _settleFrom = 0;

  static const _sideBand = 0.3;
  static const _closeDistance = 110.0;
  static const _closeVelocity = 700.0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pages.dispose();
    _settle.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.items.length) return;
    _pages.animateToPage(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _close() => Navigator.of(context).maybePop();

  void _onTapUp(TapUpDetails d) {
    final width = context.size?.width ?? 1;
    final x = d.localPosition.dx / width;
    if (x < _sideBand) {
      _go(-1);
    } else if (x > 1 - _sideBand) {
      _go(1);
    } else {
      _close();
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_dragDy.abs() > _closeDistance || v.abs() > _closeVelocity) {
      _close();
      return;
    }
    _settleFrom = _dragDy;
    _settle.forward(from: 0);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _go(-1);
      case LogicalKeyboardKey.arrowRight:
        _go(1);
      case LogicalKeyboardKey.escape:
        _close();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final fade = (1 - _dragDy.abs() / 400).clamp(0.0, 1.0);
    final item = widget.items[_index];

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: Colors.black.withValues(alpha: fade),
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _onTapUp,
              // While zoomed, vertical drags pan the photo instead of closing.
              onVerticalDragUpdate: _zoomed ? null : (d) => setState(() => _dragDy += d.delta.dy),
              onVerticalDragEnd: _zoomed ? null : _onDragEnd,
              child: Transform.translate(
                offset: Offset(0, _dragDy),
                child: Transform.scale(
                  scale: 1 - math.min(_dragDy.abs() / 2000, 0.15),
                  child: PhotoViewGallery.builder(
                    itemCount: widget.items.length,
                    pageController: _pages,
                    backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                    onPageChanged: (i) => setState(() {
                      _index = i;
                      _zoomed = false;
                    }),
                    scaleStateChangedCallback: (s) =>
                        setState(() => _zoomed = s != PhotoViewScaleState.initial),
                    builder: (context, i) => _page(app, i),
                  ),
                ),
              ),
            ),
            _TopBar(
              title: item.name,
              subtitle: '${_index + 1} / ${widget.items.length}',
              opacity: fade,
              onBack: _close,
            ),
          ],
        ),
      ),
    );
  }

  PhotoViewGalleryPageOptions _page(AppState app, int i) {
    final item = widget.items[i];
    final hero = i == widget.initialIndex
        ? PhotoViewHeroAttributes(tag: '${widget.source.id}|${item.path}')
        : null;

    if (item.isVideo) {
      return PhotoViewGalleryPageOptions.customChild(
        heroAttributes: hero,
        disableGestures: true,
        child: VideoPage(
          source: widget.source,
          item: item,
          active: i == _index,
          autoplay: app.autoplayVideos,
        ),
      );
    }

    return PhotoViewGalleryPageOptions.customChild(
      heroAttributes: hero,
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.contained * 8,
      child: _FullImage(source: widget.source, item: item),
    );
  }
}

class _FullImage extends StatefulWidget {
  const _FullImage({required this.source, required this.item});
  final MediaSource source;
  final MediaItem item;

  @override
  State<_FullImage> createState() => _FullImageState();
}

class _FullImageState extends State<_FullImage> {
  late final Future<File> _file = widget.item.localPath != null
      ? Future.value(File(widget.item.localPath!))
      : widget.source.localFile(widget.item);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snap) {
        if (snap.hasError) return _error('${snap.error}');
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.white70));
        }
        return Image.file(
          snap.data!,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, e, _) => _error('Can\'t open ${widget.item.name}'),
        );
      },
    );
  }

  Widget _error(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.opacity,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final double opacity;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBack,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15)),
                    Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}
