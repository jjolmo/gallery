import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallery/core/app_state.dart';
import 'package:gallery/core/models.dart';
import 'package:gallery/ui/home.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('menu shows 6 folders, the rest open below a fixed toggle', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.initForTest();
    FolderRef f(String name) =>
        FolderRef(title: name, sourceId: 'local', path: '/$name');
    state.localFolders = [f('Camera'), f('Screenshots'), f('Download')];
    state.otherFolders = [for (var i = 1; i <= 6; i++) f('Other$i')];
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      AppScope(
        state: state,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    // The grid behind keeps a spinner going, so step time instead of settling.
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await settle();
    await tester.tap(find.byIcon(Icons.menu));
    await settle();

    for (final name in [
      'Camera',
      'Screenshots',
      'Download',
      'Other1',
      'Other2',
      'Other3',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Other4'), findsNothing);
    final more = find.text('View more (3)');
    expect(more, findsOneWidget);
    final where = tester.getTopLeft(more);

    await tester.tap(more);
    await settle();
    final less = find.text('View less');
    expect(less, findsOneWidget);
    expect(tester.getTopLeft(less), where);
    for (final name in ['Other4', 'Other5', 'Other6']) {
      expect(tester.getTopLeft(find.text(name)).dy, greaterThan(where.dy));
    }

    await tester.tap(less);
    await settle();
    expect(find.text('Other4'), findsNothing);
    expect(find.text('View more (3)'), findsOneWidget);
  });
}
