import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallery/core/app_state.dart';
import 'package:gallery/core/models.dart';
import 'package:gallery/core/view_options.dart';
import 'package:gallery/sources/source.dart';
import 'package:gallery/ui/folder_screen.dart';
import 'package:gallery/ui/thumbnail.dart';
import 'package:shared_preferences/shared_preferences.dart';

MediaItem _item(String name, int day) => MediaItem(
  path: name,
  name: name,
  kind: kindFromName(name)!,
  modified: DateTime(2020, 1, day),
);

/// Three pages of 150, newest first; the only video is on the last page.
class _PagedSource extends MediaSource {
  int pagesServed = 0;

  @override
  String get id => 'local';

  List<MediaItem> _page(int n) => [
    for (var i = 0; i < 150; i++)
      n == 2 && i == 149 ? _item('clip.mp4', 1) : _item('p${n}_$i.jpg', 28 - n),
  ];

  @override
  Future<Listing> list(String path) async {
    pagesServed = 1;
    var next = 1;
    return Listing(
      [],
      _page(0),
      more: () async {
        if (next > 2) return [];
        pagesServed++;
        return _page(next++);
      },
    );
  }

  @override
  Future<File> localFile(MediaItem item) async => File('/nonexistent');
}

void main() {
  test('applyView filters by type and sorts', () {
    final items = [_item('b.jpg', 3), _item('a.gif', 1), _item('c.mp4', 2)];
    expect(applyView(items, MediaFilter.all, SortOrder.newest), same(items));
    expect(
      applyView(items, MediaFilter.videos, SortOrder.newest).map((m) => m.name),
      ['c.mp4'],
    );
    expect(
      applyView(items, MediaFilter.all, SortOrder.nameAz).map((m) => m.name),
      ['a.gif', 'b.jpg', 'c.mp4'],
    );
    expect(
      applyView(items, MediaFilter.all, SortOrder.oldest).map((m) => m.name),
      ['a.gif', 'c.mp4', 'b.jpg'],
    );
  });

  Future<_PagedSource> pump(
    WidgetTester tester,
    Map<String, Object> prefs,
  ) async {
    SharedPreferences.setMockInitialValues(prefs);
    final source = _PagedSource();
    final state = AppState();
    await state.initForTest(local: source);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: FolderScreen(
            folder: FolderRef(title: 'T', sourceId: 'local', path: 'x'),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return source;
  }

  testWidgets('newest first only loads the first page', (tester) async {
    final source = await pump(tester, {});
    expect(source.pagesServed, 1);
  });

  testWidgets('sorting by name loads every page', (tester) async {
    final source = await pump(tester, {'sort': 'nameAz'});
    expect(source.pagesServed, 3);
  });

  testWidgets('a filter keeps paging until it finds matches', (tester) async {
    final source = await pump(tester, {'filter': 'videos'});
    expect(source.pagesServed, 3);
    expect(find.byType(MediaThumb), findsOneWidget);
  });
}
