import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/view_options.dart';
import '../sources/source.dart';
import 'media_grid.dart';
import 'view_buttons.dart';

/// Everything inside a folder and its subfolders, in one grid. It fills in as
/// the walk finds media, and the viewer keeps up with it.
class RecursiveScreen extends StatefulWidget {
  const RecursiveScreen({super.key, required this.folder});
  final FolderRef folder;

  @override
  State<RecursiveScreen> createState() => _RecursiveScreenState();
}

class _RecursiveScreenState extends State<RecursiveScreen> {
  final _items = <MediaItem>[];
  final _grew = ValueNotifier(0);
  StreamSubscription<List<MediaItem>>? _walk;
  late final MediaSource _source;
  bool _done = false;
  Object? _error;
  SortOrder _sort = SortOrder.folder;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _source = app.sourceFor(widget.folder.sourceId);
    _walk = _source
        .walk(widget.folder.path)
        .listen(
          (batch) {
            _items.addAll(batch);
            _grew.value++;
            setState(() {});
          },
          onError: (Object e) => setState(() => _error = e),
          onDone: () => setState(() => _done = true),
        );
  }

  @override
  void dispose() {
    _walk?.cancel();
    _grew.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // In walk order with no filter the grid and the viewer share the growing
    // list, so swiping follows new finds. Otherwise they get a sorted copy.
    final live = app.filter == MediaFilter.all && _sort == SortOrder.folder;
    final shown = live ? _items : applyView(_items, app.filter, _sort);
    final count = '${shown.length} ${shown.length == 1 ? 'item' : 'items'}';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.folder.title),
            Text(
              _done
                  ? 'All subfolders · $count'
                  : 'Searching subfolders… $count',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          ViewButtons(
            filter: app.filter,
            sort: _sort,
            sorts: SortOrder.forWalk,
            onFilter: (f) => app.filter = f,
            onSort: (s) => setState(() => _sort = s),
          ),
        ],
        bottom: _done || _error != null
            ? null
            : const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              ),
      ),
      body: _error != null && shown.isEmpty
          ? Center(child: Text('$_error', textAlign: TextAlign.center))
          : _done && shown.isEmpty
          ? const Center(child: Text('No photos or videos in this folder'))
          : CustomScrollView(
              slivers: [
                MediaGridSliver(
                  source: _source,
                  items: shown,
                  updates: live ? _grew : null,
                ),
              ],
            ),
    );
  }
}

/// Long-press menu for a folder.
Future<void> showFolderActions(
  BuildContext context,
  FolderRef folder, {
  required VoidCallback onOpen,
  List<Widget> extra = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(folder.title),
            subtitle: folder.subtitle == null ? null : Text(folder.subtitle!),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Open'),
            onTap: () {
              Navigator.pop(sheet);
              onOpen();
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Show everything inside'),
            subtitle: const Text('Photos and videos from all subfolders'),
            onTap: () {
              Navigator.pop(sheet);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RecursiveScreen(folder: folder),
                ),
              );
            },
          ),
          ...extra,
        ],
      ),
    ),
  );
}
