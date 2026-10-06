import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/models.dart';
import 'remote_config.dart';
import 'source.dart';

/// Seafile through its Web API v2. Paths are paths inside the configured library.
class SeafileSource extends RemoteSource {
  SeafileSource(this.config)
    : _server = config.host.replaceAll(RegExp(r'/+$'), '');
  final RemoteConfig config;
  final String _server;
  final _http = http.Client();

  String? _token;
  String? _repoId;

  @override
  String get id => config.id;

  Future<Map<String, String>> _headers() async {
    _token ??= await _login();
    return {'Authorization': 'Token $_token', 'Accept': 'application/json'};
  }

  Future<String> _login() async {
    final res = await _http.post(
      Uri.parse('$_server/api2/auth-token/'),
      body: {'username': config.username, 'password': config.password},
    );
    if (res.statusCode != 200) {
      throw HttpException('Seafile login failed (${res.statusCode})');
    }
    return (jsonDecode(res.body) as Map)['token'] as String;
  }

  Future<String> _repo() async {
    if (_repoId != null) return _repoId!;
    final res = await _http.get(
      Uri.parse('$_server/api2/repos/'),
      headers: await _headers(),
    );
    _check(res);
    final repos = (jsonDecode(res.body) as List).cast<Map>();
    final match = repos.where((r) => r['name'] == config.library).toList();
    if (match.isEmpty) {
      throw HttpException('Library "${config.library}" not found');
    }
    return _repoId = match.first['id'] as String;
  }

  void _check(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) _token = null;
    if (res.statusCode != 200) {
      throw HttpException('Seafile ${res.statusCode}', uri: res.request?.url);
    }
  }

  Uri _api(
    String repo,
    String endpoint,
    String path, [
    Map<String, String>? extra,
  ]) =>
      Uri.parse('$_server/api2/repos/$repo/$endpoint/')
          .replace(queryParameters: {'p': path, ...?extra});

  @override
  Future<Listing> list(String path) async {
    final repo = await _repo();
    final res = await _http.get(
      _api(repo, 'dir', path),
      headers: await _headers(),
    );
    _check(res);
    final folders = <FolderEntry>[];
    final media = <MediaItem>[];
    for (final e
        in (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map>()) {
      final name = e['name'] as String;
      if (isHiddenName(name)) continue;
      final full = p.posix.join(path, name);
      if (e['type'] == 'dir') {
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
            ((e['mtime'] as num?) ?? 0).toInt() * 1000,
          ),
          size: (e['size'] as num?)?.toInt(),
        ),
      );
    }
    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    sortNewestFirst(media);
    return Listing(folders, media);
  }

  /// Server-side thumbnails save downloading full photos just for the grid.
  @override
  Future<Uint8List?> thumbnail(MediaItem item, int size) async {
    if (item.kind == MediaKind.video) return null;
    try {
      final repo = await _repo();
      final res = await _http.get(
        _api(repo, 'thumbnail', item.path, {'size': '$size'}),
        headers: await _headers(),
      );
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode == 200 && type.startsWith('image/')) {
        return res.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> download(String path, File target) async {
    final repo = await _repo();
    final res = await _http.get(
      _api(repo, 'file', path),
      headers: await _headers(),
    );
    _check(res);
    // The API answers with a one-time download link as a JSON string.
    final link = jsonDecode(res.body) as String;
    final dl = await _http.send(http.Request('GET', Uri.parse(link)));
    if (dl.statusCode != 200) {
      throw HttpException('Seafile download ${dl.statusCode}');
    }
    final sink = target.openWrite();
    try {
      await sink.addStream(dl.stream);
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> close() async => _http.close();
}
