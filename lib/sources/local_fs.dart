import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../core/models.dart';
import 'source.dart';

const recentPath = '__recent__';

/// Plain filesystem source, used for local folders on Linux.
class LocalFsSource extends MediaSource {
  LocalFsSource(this.roots);

  /// Folders merged into the "Recent" view.
  final List<String> roots;

  @override
  String get id => 'local';

  @override
  Future<Listing> list(String path) {
    if (path == recentPath) {
      final roots = this.roots;
      return Isolate.run(() => Listing([], _scanRecent(roots)));
    }
    return Isolate.run(() => _listDir(path));
  }

  @override
  Future<File> localFile(MediaItem item) async =>
      File(item.localPath ?? item.path);
}

Listing _listDir(String path) {
  final folders = <FolderEntry>[];
  final media = <MediaItem>[];
  for (final e in Directory(path).listSync(followLinks: true)) {
    final name = p.basename(e.path);
    if (isHiddenName(name)) continue;
    if (e is Directory) {
      folders.add(FolderEntry(name, e.path));
    } else if (e is File) {
      final item = _itemFor(e);
      if (item != null) media.add(item);
    }
  }
  folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  sortNewestFirst(media);
  return Listing(folders, media);
}

const _recentLimit = 3000;
const _recentDepth = 4;

List<MediaItem> _scanRecent(List<String> roots) {
  final seen = <String>{};
  final media = <MediaItem>[];

  void walk(Directory dir, int depth) {
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final e in entries) {
      if (isHiddenName(p.basename(e.path))) continue;
      if (e is Directory && depth < _recentDepth) {
        walk(e, depth + 1);
      } else if (e is File && seen.add(e.path)) {
        final item = _itemFor(e);
        if (item != null) media.add(item);
      }
    }
  }

  for (final r in roots) {
    final d = Directory(r);
    if (d.existsSync()) walk(d, 0);
  }
  sortNewestFirst(media);
  return media.length > _recentLimit ? media.sublist(0, _recentLimit) : media;
}

MediaItem? _itemFor(File f) {
  final name = p.basename(f.path);
  final kind = kindFromName(name);
  if (kind == null) return null;
  final stat = f.statSync();
  return MediaItem(
    path: f.path,
    name: name,
    kind: kind,
    modified: stat.modified,
    size: stat.size,
    localPath: f.path,
  );
}

/// The canonical media folders of a Linux desktop, read from XDG user dirs.
List<FolderRef> linuxDefaultFolders() {
  final home = homeDir();
  final xdg = _readXdgUserDirs(home);
  final candidates = <(String, String?)>[
    ('Pictures', xdg['XDG_PICTURES_DIR'] ?? p.join(home, 'Pictures')),
    (
      'Screenshots',
      p.join(
        xdg['XDG_PICTURES_DIR'] ?? p.join(home, 'Pictures'),
        'Screenshots',
      ),
    ),
    ('Camera', p.join(home, 'DCIM')),
    ('Videos', xdg['XDG_VIDEOS_DIR'] ?? p.join(home, 'Videos')),
    ('Downloads', xdg['XDG_DOWNLOAD_DIR'] ?? p.join(home, 'Downloads')),
    ('Desktop', xdg['XDG_DESKTOP_DIR'] ?? p.join(home, 'Desktop')),
  ];
  final out = <FolderRef>[];
  final used = <String>{};
  for (final (title, path) in candidates) {
    if (path == null || path == home || !used.add(path)) continue;
    if (!Directory(path).existsSync()) continue;
    out.add(
      FolderRef(title: title, sourceId: 'local', path: path, subtitle: path),
    );
  }
  return out;
}

Map<String, String> _readXdgUserDirs(String home) {
  final out = <String, String>{};
  final file = File(p.join(home, '.config', 'user-dirs.dirs'));
  if (!file.existsSync()) return out;
  final re = RegExp(r'^(XDG_\w+_DIR)="(.*)"$');
  for (final line in file.readAsLinesSync()) {
    final m = re.firstMatch(line.trim());
    if (m != null) out[m.group(1)!] = m.group(2)!.replaceAll(r'$HOME', home);
  }
  return out;
}
