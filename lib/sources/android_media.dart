import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../core/models.dart';
import 'local_fs.dart';
import 'source.dart';

/// Device media on Android, read from MediaStore. Albums are the "folders".
class AndroidMediaSource extends MediaSource {
  final _albums = <String, AssetPathEntity>{};
  String? _allId;

  @override
  String get id => 'android';

  static final _filter = FilterOptionGroup(
    orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
  );

  Future<bool> requestAccess() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.hasAccess;
  }

  /// Device albums split like a gallery app does: the classic ones (camera,
  /// screenshots, downloads...) and everything else. MediaStore makes an album
  /// of every folder holding an image, app caches and game assets included.
  Future<({List<FolderRef> classic, List<FolderRef> other})> albums() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
      filterOption: _filter,
    );
    final classic = <AssetPathEntity>[];
    final other = <AssetPathEntity>[];
    for (final a in paths) {
      _albums[a.id] = a;
      if (a.isAll) {
        _allId = a.id;
      } else if (_classicAlbums.contains(a.name.toLowerCase())) {
        classic.add(a);
      } else {
        other.add(a);
      }
    }
    int rank(AssetPathEntity a) => _classicAlbums.indexOf(a.name.toLowerCase());
    classic.sort((x, y) => rank(x).compareTo(rank(y)));
    other.sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
    FolderRef ref(AssetPathEntity a) =>
        FolderRef(title: a.name, sourceId: id, path: a.id);
    return (classic: classic.map(ref).toList(), other: other.map(ref).toList());
  }

  static const _classicAlbums = [
    'camera',
    'screenshots',
    'screen recordings',
    'screenrecorder',
    'download',
    'downloads',
    'pictures',
    'movies',
    'videos',
    'whatsapp images',
    'whatsapp video',
    'telegram',
    'instagram',
  ];

  /// Folders whose media belongs in Recent. Anything else (app data, caches,
  /// stickers) is still reachable from its own album.
  static const _recentRoots = [
    'dcim/',
    'pictures/',
    'download/',
    'movies/',
    'android/media/com.whatsapp/whatsapp/media/whatsapp images',
    'android/media/com.whatsapp/whatsapp/media/whatsapp video',
    'whatsapp/media/whatsapp images',
    'whatsapp/media/whatsapp video',
  ];

  static bool _inRecent(AssetEntity a) {
    // Before Android 10 there is no relative path; keep everything then.
    final rel = a.relativePath?.toLowerCase();
    if (rel == null) return true;
    if (rel.contains('/.')) return false;
    return _recentRoots.any(rel.startsWith);
  }

  static const _firstPage = 120;
  static const _nextPage = 400;

  Future<AssetPathEntity?> _album(String path) async {
    if (path != recentPath) {
      if (_albums.isEmpty) await albums();
      return _albums[path];
    }
    if (_allId == null) {
      final all = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
        filterOption: _filter,
      );
      if (all.isEmpty) return null;
      _albums[all.first.id] = all.first;
      _allId = all.first.id;
    }
    return _albums[_allId];
  }

  /// Returns the newest page right away; the grid pulls the rest as it scrolls.
  @override
  Future<Listing> list(String path) async {
    final album = await _album(path);
    if (album == null) return Listing([], []);
    final recent = path == recentPath;
    var cursor = 0;
    var done = false;

    // Recent skips non-classic folders, so a page may need several reads.
    Future<List<MediaItem>> next(int want) async {
      final out = <MediaItem>[];
      while (!done && out.length < want) {
        final assets = await album.getAssetListRange(
          start: cursor,
          end: cursor + _nextPage,
        );
        cursor += assets.length;
        if (assets.length < _nextPage) done = true;
        for (final a in assets) {
          if (recent && !_inRecent(a)) continue;
          final item = _toItem(a);
          if (item != null) out.add(item);
        }
      }
      return out;
    }

    return Listing([], await next(_firstPage), more: () => next(_nextPage));
  }

  MediaItem? _toItem(AssetEntity a) {
    final name = a.title ?? a.id;
    final MediaKind kind;
    if (a.type == AssetType.video) {
      kind = MediaKind.video;
    } else if (a.type == AssetType.image) {
      final gif =
          a.mimeType == 'image/gif' || name.toLowerCase().endsWith('.gif');
      kind = gif ? MediaKind.gif : MediaKind.image;
    } else {
      return null;
    }
    return MediaItem(
      path: a.id,
      name: name,
      kind: kind,
      modified: a.createDateTime,
      size: null,
      handle: a,
    );
  }

  @override
  Future<Uint8List?> thumbnail(MediaItem item, int size) =>
      (item.handle as AssetEntity).thumbnailDataWithSize(
        ThumbnailSize.square(size),
      );

  @override
  Future<File> localFile(MediaItem item) async {
    final file = await (item.handle as AssetEntity).file;
    if (file == null) {
      throw FileSystemException('Media not available', item.name);
    }
    return file;
  }
}
