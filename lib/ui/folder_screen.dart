import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../sources/source.dart';
import 'thumbnail.dart';
import 'viewer.dart';

/// A folder's subfolders and a grid of its media.
class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.folder, this.drawer});

  final FolderRef folder;

  /// Only the root screen has the navigation drawer; pushed ones get a back arrow.
  final Widget? drawer;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  late Future<Listing> _listing;

  // Media shown so far; big folders arrive in pages as the grid scrolls.
  List<MediaItem> _media = [];
  Future<List<MediaItem>> Function(int offset)? _more;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _listing = _load();
  }

  MediaSource get _source =>
      AppScope.read(context).sourceFor(widget.folder.sourceId);

  Future<Listing> _load() {
    final app = AppScope.read(context);
    // Device media can't be listed before the permission flow has run.
    if (!widget.folder.remote && (!app.localReady || !app.hasMediaAccess)) {
      return Future.value(Listing([], []));
    }
    return _source.list(widget.folder.path).then((l) {
      _media = List.of(l.media);
      _more = l.more;
      return l;
    });
  }

  Future<void> _loadMore() async {
    final more = _more;
    if (more == null || _loadingMore || !mounted) return;
    _loadingMore = true;
    try {
      final next = await more(_media.length);
      if (!mounted) return;
      setState(() {
        _media.addAll(next);
        if (next.isEmpty) _more = null;
      });
    } catch (_) {
      _more = null;
    } finally {
      _loadingMore = false;
    }
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _listing = f);
    await f.catchError((_) => Listing([], []));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      drawer: widget.drawer,
      appBar: AppBar(
        title: Text(widget.folder.title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: !app.localReady && !widget.folder.remote
          ? const Center(child: CircularProgressIndicator())
          : !app.hasMediaAccess && !widget.folder.remote
          ? _NoAccess(
              onRetry: () async {
                await app.reloadLocal();
                await _refresh();
              },
            )
          : FutureBuilder<Listing>(
              future: _listing,
              builder: (context, snap) {
                if (snap.hasError) {
                  return _Message(
                    icon: Icons.cloud_off,
                    text: '${snap.error}',
                    action: FilledButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _content(app, snap.data!);
              },
            ),
    );
  }

  Widget _content(AppState app, Listing listing) {
    final media = app.showVideos
        ? _media
        : _media.where((m) => !m.isVideo).toList();
    if (listing.folders.isEmpty && media.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const [
            SizedBox(height: 160),
            _Message(
              icon: Icons.photo_library_outlined,
              text: 'No photos or videos here',
            ),
          ],
        ),
      );
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final thumbPx = (width / app.columns * dpr).clamp(64, 1024).round();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        slivers: [
          SliverList.builder(
            itemCount: listing.folders.length,
            itemBuilder: (context, i) {
              final f = listing.folders[i];
              return ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f.name),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FolderScreen(
                      folder: FolderRef(
                        title: f.name,
                        sourceId: widget.folder.sourceId,
                        path: f.path,
                        remote: widget.folder.remote,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          SliverPadding(
            padding: const EdgeInsets.all(2),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: app.columns,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: media.length,
              itemBuilder: (context, i) {
                if (_more != null && i > media.length - 90) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _loadMore(),
                  );
                }
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      pageBuilder: (_, _, _) => ViewerScreen(
                        source: _source,
                        items: media,
                        initialIndex: i,
                      ),
                      transitionsBuilder: (_, anim, _, child) =>
                          FadeTransition(opacity: anim, child: child),
                    ),
                  ),
                  child: Hero(
                    tag: '${_source.id}|${media[i].path}',
                    child: MediaThumb(
                      source: _source,
                      item: media[i],
                      size: thumbPx,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _Message(
      icon: Icons.lock_outline,
      text: 'Gallery needs access to your photos and videos.',
      action: Wrap(
        spacing: 8,
        children: [
          FilledButton(onPressed: onRetry, child: const Text('Grant access')),
          if (Platform.isAndroid)
            OutlinedButton(
              onPressed: PhotoManager.openSetting,
              child: const Text('Open settings'),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: s.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: s.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
