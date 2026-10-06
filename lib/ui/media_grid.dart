import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../sources/source.dart';
import 'thumbnail.dart';
import 'viewer.dart';

void openViewer(
  BuildContext context,
  MediaSource source,
  List<MediaItem> items,
  int index, {
  Listenable? updates,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      pageBuilder: (_, _, _) => ViewerScreen(
        source: source,
        items: items,
        initialIndex: index,
        updates: updates,
      ),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

/// The thumbnail grid, as a sliver so screens can put folders above it.
class MediaGridSliver extends StatelessWidget {
  const MediaGridSliver({
    super.key,
    required this.source,
    required this.items,
    this.onNearEnd,
    this.updates,
  });

  final MediaSource source;
  final List<MediaItem> items;

  /// Called while the last rows are being built, to fetch the next page.
  final VoidCallback? onNearEnd;

  /// Passed to the viewer when [items] keeps growing after it opens.
  final Listenable? updates;

  @override
  Widget build(BuildContext context) {
    final columns = AppScope.of(context).columns;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final thumbPx = (width / columns * dpr).clamp(64, 1024).round();

    return SliverPadding(
      padding: const EdgeInsets.all(2),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          if (onNearEnd != null && i > items.length - 90) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onNearEnd!());
          }
          return GestureDetector(
            onTap: () =>
                openViewer(context, source, items, i, updates: updates),
            child: Hero(
              tag: '${source.id}|${items[i].path}',
              child: MediaThumb(source: source, item: items[i], size: thumbPx),
            ),
          );
        },
      ),
    );
  }
}
