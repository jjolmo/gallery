import 'package:flutter_test/flutter_test.dart';
import 'package:gallery/core/models.dart';

void main() {
  test('media kind comes from the extension', () {
    expect(kindFromName('IMG_0001.JPG'), MediaKind.image);
    expect(kindFromName('cat.gif'), MediaKind.gif);
    expect(kindFromName('clip.mp4'), MediaKind.video);
    expect(kindFromName('notes.txt'), isNull);
  });
}
