import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../sources/source.dart';
import 'media_grid.dart';

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

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _source = app.sourceFor(widget.folder.sourceId);
    final showVideos = app.showVideos;
    _walk = _source
        .walk(widget.folder.path)
        .listen(
          (batch) {
            _items.addAll(showVideos ? batch : batch.where((m) => !m.isVideo));
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
    final count = '${_items.length} ${_items.length == 1 ? 'item' : 'items'}';
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
        bottom: _done || _error != null
            ? null
            : const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              ),
      ),
      body: _error != null && _items.isEmpty
          ? Center(child: Text('$_error', textAlign: TextAlign.center))
          : _done && _items.isEmpty
          ? const Center(child: Text('No photos or videos in this folder'))
          : CustomScrollView(
              slivers: [
                MediaGridSliver(source: _source, items: _items, updates: _grew),
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
