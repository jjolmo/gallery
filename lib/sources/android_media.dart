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

  /// One folder per album, the usual camera folders first. Albums aren't
  /// counted: that is a MediaStore query per album and made startup slow.
  Future<List<FolderRef>> albums() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
      filterOption: _filter,
    );
    final albums = <AssetPathEntity>[];
    for (final a in paths) {
      _albums[a.id] = a;
      if (a.isAll) {
        _allId = a.id;
      } else {
        albums.add(a);
      }
    }
    int rank(AssetPathEntity a) {
      final i = _firstAlbums.indexOf(a.name.toLowerCase());
      return i < 0 ? _firstAlbums.length : i;
    }

    albums.sort((x, y) {
      final r = rank(x).compareTo(rank(y));
      return r != 0 ? r : x.name.toLowerCase().compareTo(y.name.toLowerCase());
    });
    return [
      for (final a in albums)
        FolderRef(title: a.name, sourceId: id, path: a.id),
    ];
  }

  static const _firstAlbums = ['camera', 'screenshots', 'download', 'pictures'];
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

    Future<List<MediaItem>> range(int start, int count) async {
      final assets = await album.getAssetListRange(
        start: start,
        end: start + count,
      );
      return [for (final a in assets) ?_toItem(a)];
    }

    return Listing(
      [],
      await range(0, _firstPage),
      more: (offset) => range(offset, _nextPage),
    );
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
