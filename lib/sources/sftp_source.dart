import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/video_frames.dart';
import 'remote_config.dart';
import 'source.dart';

class SftpSource extends RemoteSource {
  SftpSource(this.config);
  final RemoteConfig config;

  SSHClient? _client;
  Future<SftpClient>? _sftp;

  @override
  String get id => config.id;

  Future<SftpClient> _connect() {
    return _sftp ??= () async {
      try {
        final socket = await SSHSocket.connect(
          config.host,
          config.port ?? 22,
          timeout: const Duration(seconds: 15),
        );
        final key = config.privateKey.trim();
        final client = SSHClient(
          socket,
          username: config.username,
          identities: key.isEmpty
              ? null
              : SSHKeyPair.fromPem(
                  key,
                  config.password.isEmpty ? null : config.password,
                ),
          onPasswordRequest: () => config.password,
        );
        _client = client;
        // Drop the cached connection when the server closes it, so the next
        // call reconnects instead of failing forever.
        client.done.whenComplete(() {
          _sftp = null;
          _client = null;
        });
        return await client.sftp();
      } catch (_) {
        _sftp = null;
        rethrow;
      }
    }();
  }

  @override
  Future<Listing> list(String path) async {
    final sftp = await _connect();
    final folders = <FolderEntry>[];
    final media = <MediaItem>[];
    for (final e in await sftp.listdir(path)) {
      final name = e.filename;
      if (name == '.' || name == '..' || isHiddenName(name)) continue;
      final full = p.posix.join(path, name);
      if (e.attr.isDirectory) {
        folders.add(FolderEntry(name, full));
        continue;
      }
      final kind = kindFromName(name);
      if (kind == null) continue;
      media.add(
        MediaItem(
          path: full,
          name: name,
          kind: kind,
          modified: DateTime.fromMillisecondsSinceEpoch(
            (e.attr.modifyTime ?? 0) * 1000,
          ),
          size: e.attr.size,
        ),
      );
    }
    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    sortNewestFirst(media);
    return Listing(folders, media);
  }

  /// SFTP can't be streamed by the frame grabbers, so small videos are
  /// downloaded (and cached for playback); big ones keep the placeholder.
  @override
  Future<VideoInput?> videoInput(MediaItem item) async {
    final size = item.size;
    if (size == null || size > _maxThumbDownload) return null;
    return VideoInput.file((await localFile(item)).path);
  }

  static const _maxThumbDownload = 40 * 1024 * 1024;

  @override
  Future<void> download(String path, File target) async {
    final sftp = await _connect();
    final remote = await sftp.open(path);
    final sink = target.openWrite();
    try {
      await sink.addStream(remote.read());
    } finally {
      await sink.close();
      await remote.close();
    }
  }

  @override
  Future<void> close() async {
    _client?.close();
    _client = null;
    _sftp = null;
  }
}
