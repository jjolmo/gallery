import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gallery/sources/local_fs.dart';

void main() {
  test('walk finds media in every subfolder, top folder first', () async {
    final root = Directory.systemTemp.createTempSync('walk');
    void touch(String rel) => (File(
      '${root.path}/$rel',
    )..createSync(recursive: true)).writeAsStringSync('x');
    touch('top.jpg');
    touch('a/one.png');
    touch('a/deep/two.gif');
    touch('b/three.mp4');
    touch('b/notes.txt');
    touch('.hidden/secret.jpg');

    final batches = await LocalFsSource([]).walk(root.path).toList();
    final names = [
      for (final b in batches)
        for (final m in b) m.name,
    ];

    expect(names.first, 'top.jpg');
    expect(names.toSet(), {'top.jpg', 'one.png', 'two.gif', 'three.mp4'});
    root.deleteSync(recursive: true);
  });
}
