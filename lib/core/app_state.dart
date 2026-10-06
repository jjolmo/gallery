import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../sources/android_media.dart';
import '../sources/local_fs.dart';
import '../sources/remote_config.dart';
import '../sources/seafile_source.dart';
import '../sources/sftp_source.dart';
import '../sources/source.dart';
import '../sources/webdav_source.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;
  late MediaSource localSource;
  final _remoteSources = <String, MediaSource>{};

  List<FolderRef> localFolders = [];

  /// Device albums outside the classic set, shown collapsed in the menu.
  List<FolderRef> otherFolders = [];
  List<RemoteConfig> remotes = [];
  bool hasMediaAccess = true;

  /// False until device folders are known. On Android that needs the media
  /// permission, which is asked after the first frame: asking before runApp
  /// leaves a black screen behind the dialog, or forever if it never shows.
  bool localReady = false;

  int get columns => _prefs.getInt('columns') ?? 3;
  set columns(int v) => _set(() => _prefs.setInt('columns', v));

  bool get showVideos => _prefs.getBool('showVideos') ?? true;
  set showVideos(bool v) => _set(() => _prefs.setBool('showVideos', v));

  bool get autoplayVideos => _prefs.getBool('autoplayVideos') ?? true;
  set autoplayVideos(bool v) => _set(() => _prefs.setBool('autoplayVideos', v));

  ThemeMode get themeMode => ThemeMode.values.byName(
    _prefs.getString('themeMode') ?? ThemeMode.dark.name,
  );
  set themeMode(ThemeMode v) =>
      _set(() => _prefs.setString('themeMode', v.name));

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }

  FolderRef get recent =>
      FolderRef(title: 'Recent', sourceId: localSource.id, path: recentPath);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    remotes = await _loadRemotes();
    if (Platform.isAndroid) {
      localSource = AndroidMediaSource();
    } else {
      await reloadLocal();
    }
  }

  @visibleForTesting
  Future<void> initForTest() async {
    _prefs = await SharedPreferences.getInstance();
    localSource = LocalFsSource([]);
    localReady = true;
  }

  Future<void> reloadLocal() async {
    if (Platform.isAndroid) {
      final android = AndroidMediaSource();
      localSource = android;
      hasMediaAccess = await android.requestAccess();
      localFolders = [];
      // Recent doesn't need the album list, so show it before loading albums.
      localReady = true;
      notifyListeners();
      if (hasMediaAccess) {
        final albums = await android.albums();
        localFolders = albums.classic;
        otherFolders = albums.other;
      }
    } else {
      localFolders = linuxDefaultFolders();
      localSource = LocalFsSource([for (final f in localFolders) f.path]);
    }
    localReady = true;
    notifyListeners();
  }

  MediaSource sourceFor(String id) {
    if (id == localSource.id) return localSource;
    return _remoteSources.putIfAbsent(id, () {
      final c = remotes.firstWhere((r) => r.id == id);
      return switch (c.type) {
        RemoteType.sftp => SftpSource(c),
        RemoteType.webdav => WebDavSource(c),
        RemoteType.seafile => SeafileSource(c),
      };
    });
  }

  FolderRef folderForRemote(RemoteConfig c) {
    final String path;
    if (c.type == RemoteType.webdav) {
      path = WebDavSource(c).rootPath;
    } else {
      path = c.path.isEmpty ? '/' : c.path;
    }
    return FolderRef(
      title: c.name,
      sourceId: c.id,
      path: path,
      subtitle: c.type.label,
      remote: true,
    );
  }

  Future<void> saveRemote(RemoteConfig c) async {
    final i = remotes.indexWhere((r) => r.id == c.id);
    if (i >= 0) {
      remotes[i] = c;
      await _remoteSources.remove(c.id)?.close();
    } else {
      remotes.add(c);
    }
    await _storeRemotes();
    notifyListeners();
  }

  Future<void> deleteRemote(String id) async {
    remotes.removeWhere((r) => r.id == id);
    await _remoteSources.remove(id)?.close();
    await _storeRemotes();
    notifyListeners();
  }

  // Credentials live in a private file rather than the system keyring: many
  // ARM Linux boards run without a Secret Service, and then nothing would work.
  Future<File> get _remotesFile async => File(
    p.join((await getApplicationSupportDirectory()).path, 'remotes.json'),
  );

  Future<List<RemoteConfig>> _loadRemotes() async {
    try {
      final f = await _remotesFile;
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return [
        for (final j in list) RemoteConfig.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _storeRemotes() async {
    final f = await _remotesFile;
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode([for (final r in remotes) r.toJson()]));
    if (!Platform.isAndroid) await Process.run('chmod', ['600', f.path]);
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
