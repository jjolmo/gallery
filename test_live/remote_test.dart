// Live checks against real servers; not part of CI. Run with
// `flutter test test_live` after starting the servers described in each test.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gallery/core/models.dart';
import 'package:gallery/sources/remote_config.dart';
import 'package:gallery/sources/sftp_source.dart';
import 'package:gallery/sources/webdav_source.dart';

void main() {
  final dir = Platform.environment['GALLERY_TEST_DIR'] ?? '/tmp/gallery-remote';

  test('sftp lists and downloads', () async {
    final s = SftpSource(RemoteConfig(
      id: 'sftp',
      type: RemoteType.sftp,
      name: 'local',
      host: Platform.environment['SFTP_HOST'] ?? '127.0.0.1',
      port: int.parse(Platform.environment['SFTP_PORT'] ?? '22'),
      username: Platform.environment['SFTP_USER'] ?? Platform.environment['USER']!,
      privateKey: File('${Platform.environment['HOME']}/.ssh/id_ed25519').readAsStringSync(),
    ));
    final l = await s.list(dir);
    expect(l.folders.map((f) => f.name), ['sub']);
    expect(l.media.map((m) => m.name).toSet(), {'a.png', 'anim.gif'});
    expect(l.media.firstWhere((m) => m.name == 'anim.gif').kind, MediaKind.gif);
    final bytes = await File('$dir/a.png').readAsBytes();
    final tmp = File('${Directory.systemTemp.path}/sftp-a.png');
    await s.download('$dir/a.png', tmp);
    expect(await tmp.readAsBytes(), bytes);
    expect((await s.list('$dir/sub')).media.single.name, 'b.png');
    await s.close();
  });

  test('webdav lists and downloads', () async {
    final s = WebDavSource(RemoteConfig(
      id: 'dav',
      type: RemoteType.webdav,
      name: 'local',
      host: 'http://127.0.0.1:8765/dav',
      username: 'tester',
      password: 'secret',
    ));
    expect(s.rootPath, '/dav/');
    final l = await s.list(s.rootPath);
    expect(l.folders.single.path, '/dav/sub/');
    expect(l.media.map((m) => m.name).toSet(), {'a.png', 'anim.gif'});
    final tmp = File('${Directory.systemTemp.path}/dav-a.png');
    await s.download('/dav/a.png', tmp);
    expect(await tmp.readAsBytes(), await File('$dir/a.png').readAsBytes());
    expect((await s.list(l.folders.single.path)).media.single.name, 'b.png');
    await s.close();
  });
}
