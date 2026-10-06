import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../core/models.dart';
import 'remote_config.dart';
import 'source.dart';

/// WebDAV (Nextcloud, ownCloud, Apache mod_dav, rclone serve...). Paths are
/// URL paths on the server, e.g. `/remote.php/dav/files/me/Photos/`.
class WebDavSource extends RemoteSource {
  WebDavSource(this.config) : _base = Uri.parse(config.host);
  final RemoteConfig config;
  final Uri _base;
  final _http = http.Client();

  @override
  String get id => config.id;

  /// Path to open first: the URL path from the configured address.
  String get rootPath {
    final path = _base.path.isEmpty ? '/' : _base.path;
    return path.endsWith('/') ? path : '$path/';
  }

  Map<String, String> get _auth => config.username.isEmpty
      ? {}
      : {
          'Authorization':
              'Basic ${base64.encode(utf8.encode('${config.username}:${config.password}'))}',
        };

  Uri _uri(String path) => _base.replace(path: path, query: null, fragment: null);

  @override
  Future<Listing> list(String path) async {
    final req = http.Request('PROPFIND', _uri(path))
      ..headers.addAll({..._auth, 'Depth': '1', 'Content-Type': 'application/xml'})
      ..body = '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop>'
          '<d:resourcetype/><d:getlastmodified/><d:getcontentlength/>'
          '</d:prop></d:propfind>';
    final res = await http.Response.fromStream(await _http.send(req));
    if (res.statusCode != 207) {
      throw HttpException('PROPFIND ${res.statusCode}', uri: req.url);
    }

    final self = Uri.decodeFull(_uri(path).path).replaceAll(RegExp(r'/+$'), '');
    final folders = <FolderEntry>[];
    final media = <MediaItem>[];
    final doc = XmlDocument.parse(utf8.decode(res.bodyBytes));
    for (final r in doc.descendants.whereType<XmlElement>().where((e) => e.localName == 'response')) {
      final href = _text(r, 'href');
      if (href == null) continue;
      final hrefPath = Uri.decodeFull(Uri.parse(href).path);
      final trimmed = hrefPath.replaceAll(RegExp(r'/+$'), '');
      if (trimmed == self) continue;
      final name = trimmed.split('/').last;
      if (name.isEmpty || isHiddenName(name)) continue;

      final isDir = r.descendants.whereType<XmlElement>().any((e) => e.localName == 'collection');
      if (isDir) {
        folders.add(FolderEntry(name, '$trimmed/'));
        continue;
      }
      final kind = kindFromName(name);
      if (kind == null) continue;
      media.add(MediaItem(
        path: trimmed,
        name: name,
        kind: kind,
        modified: _parseHttpDate(_text(r, 'getlastmodified')),
        size: int.tryParse(_text(r, 'getcontentlength') ?? ''),
      ));
    }
    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    sortNewestFirst(media);
    return Listing(folders, media);
  }

  String? _text(XmlElement parent, String localName) {
    for (final e in parent.descendants.whereType<XmlElement>()) {
      if (e.localName == localName) return e.innerText.trim();
    }
    return null;
  }

  DateTime _parseHttpDate(String? s) {
    if (s == null) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      return HttpDate.parse(s);
    } catch (_) {
      return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  @override
  Future<void> download(String path, File target) async {
    final req = http.Request('GET', _uri(path))..headers.addAll(_auth);
    final res = await _http.send(req);
    if (res.statusCode != 200) {
      throw HttpException('GET ${res.statusCode}', uri: req.url);
    }
    final sink = target.openWrite();
    try {
      await sink.addStream(res.stream);
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> close() async => _http.close();
}
