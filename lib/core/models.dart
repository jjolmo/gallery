import 'dart:io';

import 'package:path/path.dart' as p;

enum MediaKind { image, gif, video }

const imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.bmp',
  '.heic',
  '.heif',
  '.avif',
};
const gifExtensions = {'.gif'};
const videoExtensions = {
  '.mp4',
  '.m4v',
  '.mov',
  '.webm',
  '.mkv',
  '.3gp',
  '.avi',
};

MediaKind? kindFromName(String name) {
  final ext = p.extension(name).toLowerCase();
  if (imageExtensions.contains(ext)) return MediaKind.image;
  if (gifExtensions.contains(ext)) return MediaKind.gif;
  if (videoExtensions.contains(ext)) return MediaKind.video;
  return null;
}

class MediaItem {
  MediaItem({
    required this.path,
    required this.name,
    required this.kind,
    required this.modified,
    this.size,
    this.localPath,
    this.handle,
  });

  /// Path inside its source (filesystem path, remote path or asset id).
  final String path;
  final String name;
  final MediaKind kind;
  final DateTime modified;
  final int? size;

  /// Set when the file is already on disk, so it can be shown without fetching.
  final String? localPath;

  /// Source-specific object, e.g. the Android `AssetEntity`.
  final Object? handle;

  bool get isVideo => kind == MediaKind.video;
}

class FolderEntry {
  FolderEntry(this.name, this.path);
  final String name;
  final String path;
}

class Listing {
  Listing(this.folders, this.media, {this.more});
  final List<FolderEntry> folders;
  final List<MediaItem> media;

  /// For big folders: fetches the media after [offset]; empty when done.
  final Future<List<MediaItem>> Function(int offset)? more;
}

/// A place shown in the drawer: a source plus the path to open in it.
class FolderRef {
  FolderRef({
    required this.title,
    required this.sourceId,
    required this.path,
    this.subtitle,
    this.remote = false,
  });

  final String title;
  final String sourceId;
  final String path;
  final String? subtitle;
  final bool remote;

  String get key => '$sourceId|$path';
}

void sortNewestFirst(List<MediaItem> items) =>
    items.sort((a, b) => b.modified.compareTo(a.modified));

bool isHiddenName(String name) => name.startsWith('.');

String homeDir() => Platform.environment['HOME'] ?? '/';
