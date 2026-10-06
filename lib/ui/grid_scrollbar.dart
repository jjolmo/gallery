import 'package:flutter/material.dart';

/// A gallery-style scrollbar: shows while scrolling, fades when idle, and its
/// thumb can be dragged to jump through a long grid.
class GridScrollbar extends StatefulWidget {
  const GridScrollbar({super.key, required this.builder});

  /// Builds the scroll view; it must use the given controller.
  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<GridScrollbar> createState() => _GridScrollbarState();
}

class _GridScrollbarState extends State<GridScrollbar> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RawScrollbar(
      controller: _controller,
      interactive: true,
      thickness: 8,
      // The thumb is the drag handle on touch screens, so give it a finger-sized
      // target and length.
      minThumbLength: 56,
      radius: const Radius.circular(8),
      thumbColor: scheme.primary.withValues(alpha: 0.8),
      fadeDuration: const Duration(milliseconds: 300),
      timeToFade: const Duration(milliseconds: 1200),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      // Desktop already adds a scrollbar of its own; keep only this one.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: widget.builder(context, _controller),
      ),
    );
  }
}
