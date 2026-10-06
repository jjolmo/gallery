import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallery/core/app_state.dart';
import 'package:gallery/core/models.dart';
import 'package:gallery/sources/source.dart';
import 'package:gallery/ui/viewer.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1x1 transparent PNG.
final _png = Uint8List.fromList(const [
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  156,
  99,
  0,
  1,
  0,
  0,
  5,
  0,
  1,
  13,
  10,
  45,
  180,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
]);

class _FakeSource extends MediaSource {
  @override
  String get id => 'fake';
  @override
  Future<Listing> list(String path) async => Listing([], []);
  @override
  Future<File> localFile(MediaItem item) async => File(item.localPath!);
}

void main() {
  late List<MediaItem> items;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('viewer');
    items = [
      for (var i = 0; i < 3; i++)
        MediaItem(
          path: 'p$i',
          name: 'img$i.png',
          kind: MediaKind.image,
          modified: DateTime(2020),
          localPath: (File(
            '${dir.path}/img$i.png',
          )..writeAsBytesSync(_png)).path,
        ),
    ];
  });

  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.initForTest();
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ViewerScreen(
                    source: _FakeSource(),
                    items: items,
                    initialIndex: 1,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2 / 3'), findsOneWidget);
  }

  testWidgets('tap on the bands moves between items', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(1150, 400));
    await tester.pump(); // one frame: no slide, no double-tap wait
    expect(find.bySemanticsLabel('3 / 3'), findsOneWidget);
    await tester.tapAt(const Offset(50, 400));
    await tester.pump(); // one frame: no slide, no double-tap wait
    expect(find.bySemanticsLabel('2 / 3'), findsOneWidget);
    await tester.pumpAndSettle(); // let the double-tap timer expire
  });

  testWidgets('horizontal swipe changes item', (tester) async {
    await open(tester);
    await tester.flingFrom(const Offset(900, 400), const Offset(-600, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('3 / 3'), findsOneWidget);
  });

  testWidgets('mouse wheel changes item', (tester) async {
    await open(tester);
    final g = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(g.hover(const Offset(600, 400)));
    await tester.sendEventToBinding(g.scroll(const Offset(0, 100)));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('3 / 3'), findsOneWidget);
  });

  testWidgets('viewer keeps going when the list grows', (tester) async {
    final grown = [...items.take(2)];
    final updates = ValueNotifier(0);
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.initForTest();
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: ViewerScreen(
            source: _FakeSource(),
            items: grown,
            initialIndex: 1,
            updates: updates,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2 / 2'), findsOneWidget);

    grown.add(items[2]);
    updates.value++;
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(1150, 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.bySemanticsLabel('3 / 3'), findsOneWidget);
  });

  testWidgets('only the photo is shown: no back button, no name', (
    tester,
  ) async {
    await open(tester);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.text('img1.png'), findsNothing);
    expect(find.text('2 / 3'), findsNothing);
  });

  testWidgets('tap on the center band closes', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(600, 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.byType(ViewerScreen), findsNothing);
  });

  testWidgets('vertical swipe closes', (tester) async {
    await open(tester);
    await tester.flingFrom(const Offset(600, 300), const Offset(0, 300), 1500);
    await tester.pumpAndSettle();
    expect(find.byType(ViewerScreen), findsNothing);
  });
}
