import 'models.dart';

enum MediaFilter {
  all('All'),
  photos('Photos'),
  videos('Videos'),
  gifs('GIFs');

  const MediaFilter(this.label);
  final String label;

  bool matches(MediaItem m) => switch (this) {
    MediaFilter.all => true,
    MediaFilter.photos => m.kind == MediaKind.image,
    MediaFilter.videos => m.kind == MediaKind.video,
    MediaFilter.gifs => m.kind == MediaKind.gif,
  };
}

enum SortOrder {
  newest('Newest first'),
  oldest('Oldest first'),
  nameAz('Name A–Z'),
  nameZa('Name Z–A'),

  /// As the recursive walk finds them; only offered there.
  folder('Folder order');

  const SortOrder(this.label);
  final String label;

  /// Sources list newest first, so these are the orders that need nothing
  /// done to what has been loaded so far.
  bool get keepsLoadOrder => this == newest || this == folder;

  static const forFolders = [newest, oldest, nameAz, nameZa];
  static const forWalk = [folder, newest, oldest, nameAz, nameZa];
}

/// [items] filtered and sorted, as a new list unless nothing changes.
List<MediaItem> applyView(
  List<MediaItem> items,
  MediaFilter filter,
  SortOrder sort,
) {
  if (filter == MediaFilter.all && sort.keepsLoadOrder) return items;
  final out = filter == MediaFilter.all
      ? [...items]
      : items.where(filter.matches).toList();
  int byName(MediaItem a, MediaItem b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  switch (sort) {
    case SortOrder.newest:
    case SortOrder.folder:
      break;
    case SortOrder.oldest:
      out.sort((a, b) => a.modified.compareTo(b.modified));
    case SortOrder.nameAz:
      out.sort(byName);
    case SortOrder.nameZa:
      out.sort((a, b) => byName(b, a));
  }
  return out;
}
