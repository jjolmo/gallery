import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../sources/remote_config.dart';
import 'folder_screen.dart';
import 'remote_form.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  FolderRef? _current;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppScope.read(context);
      if (!app.localReady) app.reloadLocal();
    });
  }

  void _open(FolderRef f) {
    Navigator.of(context).pop();
    setState(() => _current = f);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final current = _current ?? app.recent;
    return FolderScreen(
      // Rebuilt once device folders are ready, so Recent loads with permission.
      key: ValueKey('${current.key}|${app.localReady}'),
      folder: current,
      drawer: _drawer(app, current),
    );
  }

  Widget _drawer(AppState app, FolderRef current) {
    final theme = Theme.of(context);

    Widget tile(FolderRef f, IconData icon, {VoidCallback? onLongPress}) =>
        ListTile(
          leading: Icon(icon),
          title: Text(f.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: f.subtitle == null
              ? null
              : Text(f.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
          selected: f.key == current.key,
          onTap: () => _open(f),
          onLongPress: onLongPress,
        );

    Widget header(String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );

    return NavigationDrawer(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/icon.png', width: 40, height: 40),
              ),
              const SizedBox(width: 12),
              Text('Gallery', style: theme.textTheme.titleLarge),
            ],
          ),
        ),
        tile(app.recent, Icons.schedule),
        header('Folders'),
        for (final f in app.localFolders) tile(f, Icons.folder_outlined),
        if (app.localFolders.isEmpty)
          const ListTile(dense: true, title: Text('No media folders found')),
        header(
          'Remote folders',
          trailing: IconButton(
            tooltip: 'Add remote folder',
            icon: const Icon(Icons.add),
            onPressed: () => _editRemote(null),
          ),
        ),
        for (final r in app.remotes)
          tile(app.folderForRemote(r), switch (r.type) {
            RemoteType.sftp => Icons.terminal,
            RemoteType.webdav => Icons.cloud_outlined,
            RemoteType.seafile => Icons.cloud_sync_outlined,
          }, onLongPress: () => _remoteMenu(r)),
        if (app.remotes.isEmpty)
          ListTile(
            leading: const Icon(Icons.add_link),
            title: const Text('Add SFTP, WebDAV or Seafile'),
            onTap: () => _editRemote(null),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
          },
        ),
      ],
    );
  }

  Future<void> _editRemote(RemoteConfig? existing) async {
    Navigator.of(context).pop();
    final saved = await Navigator.of(context).push<RemoteConfig>(
      MaterialPageRoute(builder: (_) => RemoteForm(existing: existing)),
    );
    if (saved != null && mounted) {
      setState(() => _current = AppScope.read(context).folderForRemote(saved));
    }
  }

  Future<void> _remoteMenu(RemoteConfig r) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(r.name), subtitle: Text(r.type.label)),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    final app = AppScope.read(context);
    if (action == 'edit') {
      await _editRemote(r);
    } else if (action == 'delete') {
      Navigator.of(context).pop();
      if (_current?.sourceId == r.id) setState(() => _current = null);
      await app.deleteRemote(r.id);
    }
  }
}
