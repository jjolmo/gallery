enum RemoteType { sftp, webdav, seafile }

extension RemoteTypeLabel on RemoteType {
  String get label => switch (this) {
    RemoteType.sftp => 'SFTP / SSH',
    RemoteType.webdav => 'WebDAV',
    RemoteType.seafile => 'Seafile',
  };
}

class RemoteConfig {
  RemoteConfig({
    required this.id,
    required this.type,
    required this.name,
    required this.host,
    this.port,
    this.username = '',
    this.password = '',
    this.privateKey = '',
    this.path = '/',
    this.library = '',
  });

  final String id;
  final RemoteType type;
  final String name;

  /// Host name for SFTP; base URL for WebDAV and Seafile.
  final String host;
  final int? port;
  final String username;
  final String password;

  /// PEM private key for SFTP (password is used as its passphrase if set).
  final String privateKey;

  /// Folder to open, relative to the server (or to the library for Seafile).
  final String path;

  /// Seafile library name.
  final String library;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'privateKey': privateKey,
    'path': path,
    'library': library,
  };

  factory RemoteConfig.fromJson(Map<String, dynamic> j) => RemoteConfig(
    id: j['id'] as String,
    type: RemoteType.values.byName(j['type'] as String),
    name: j['name'] as String,
    host: j['host'] as String,
    port: j['port'] as int?,
    username: j['username'] as String? ?? '',
    password: j['password'] as String? ?? '',
    privateKey: j['privateKey'] as String? ?? '',
    path: j['path'] as String? ?? '/',
    library: j['library'] as String? ?? '',
  );
}
