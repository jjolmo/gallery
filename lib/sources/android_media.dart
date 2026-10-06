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

  /// One folder per non-empty album, biggest first, after "Recent".
  Future<List<FolderRef>> albums() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
      filterOption: _filter,
    );
    final counted = <(AssetPathEntity, int)>[];
    for (final a in paths) {
      _albums[a.id] = a;
      if (a.isAll) {
        _allId = a.id;
        continue;
      }
      final n = await a.assetCountAsync;
      if (n > 0) counted.add((a, n));
    }
    counted.sort((x, y) => y.$2.compareTo(x.$2));
    return [
      for (final (a, n) in counted)
        FolderRef(title: a.name, sourceId: id, path: a.id, subtitle: '$n'),
    ];
  }

  @override
  Future<Listing> list(String path) async {
    if (_albums.isEmpty) await albums();
    final album = _albums[path == recentPath ? _allId : path];
    if (album == null) return Listing([], []);
    final total = await album.assetCountAsync;
    final assets = <AssetEntity>[];
    const page = 500;
    for (var start = 0; start < total; start += page) {
      assets.addAll(
        await album.getAssetListRange(start: start, end: start + page),
      );
    }
    return Listing([], [for (final a in assets) ?_toItem(a)]);
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
