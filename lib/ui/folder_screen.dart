import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/view_options.dart';
import '../sources/local_fs.dart';
import '../sources/source.dart';
import 'grid_scrollbar.dart';
import 'media_grid.dart';
import 'recursive_screen.dart';
import 'view_buttons.dart';

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
  Future<List<MediaItem>> Function()? _more;
  bool _loadingMore = false;
  bool _loadingAll = false;

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
    if (more == null || _loadingMore || _loadingAll || !mounted) return;
    _loadingMore = true;
    try {
      final next = await more();
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

  /// Sorting by name or oldest first needs every page, not just the newest.
  Future<void> _loadAll() async {
    if (_loadingAll || _more == null) return;
    setState(() => _loadingAll = true);
    while (_loadingMore) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    try {
      while (mounted && _more != null) {
        final next = await _more!();
        if (!mounted) return;
        setState(() {
          _media.addAll(next);
          if (next.isEmpty) _more = null;
        });
      }
    } catch (_) {
      _more = null;
    } finally {
      if (mounted) setState(() => _loadingAll = false);
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
          if (widget.folder.path != recentPath)
            IconButton(
              tooltip: app.isFavorite(widget.folder)
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              icon: Icon(
                app.isFavorite(widget.folder) ? Icons.star : Icons.star_border,
              ),
              onPressed: () => app.toggleFavorite(widget.folder),
            ),
          ViewButtons(
            filter: app.filter,
            sort: app.sort,
            onFilter: (f) => app.filter = f,
            onSort: (s) => app.sort = s,
          ),
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
    final sortAll = !app.sort.keepsLoadOrder;
    if (sortAll && _more != null && !_loadingAll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
    }
    final media = applyView(_media, app.filter, app.sort);
    // A filter can leave the loaded pages nearly empty: keep fetching until
    // the grid has something to show or the folder runs out.
    if (app.filter != MediaFilter.all &&
        _more != null &&
        media.length < 60 &&
        !_loadingAll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    }
    if (listing.folders.isEmpty && media.isEmpty) {
      if (_more != null || _loadingAll) {
        return const Center(child: CircularProgressIndicator());
      }
      final what = app.filter == MediaFilter.all
          ? 'photos or videos'
          : app.filter.label.toLowerCase();
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: [
            const SizedBox(height: 160),
            _Message(icon: Icons.photo_library_outlined, text: 'No $what here'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: GridScrollbar(
        builder: (context, controller) => CustomScrollView(
          controller: controller,
          slivers: [
            if (_loadingAll)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),
            SliverList.builder(
              itemCount: listing.folders.length,
              itemBuilder: (context, i) {
                final f = listing.folders[i];
                final ref = FolderRef(
                  title: f.name,
                  sourceId: widget.folder.sourceId,
                  path: f.path,
                  remote: widget.folder.remote,
                );
                void open() => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => FolderScreen(folder: ref)),
                );
                return ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f.name),
                  onTap: open,
                  onLongPress: () =>
                      showFolderActions(context, ref, onOpen: open),
                );
              },
            ),
            MediaGridSliver(
              source: _source,
              items: media,
              onNearEnd: _more == null || sortAll ? null : _loadMore,
            ),
          ],
        ),
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
