import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../sources/remote_config.dart';
import '../sources/seafile_source.dart';
import '../sources/sftp_source.dart';
import '../sources/source.dart';
import '../sources/webdav_source.dart';

/// Add or edit a remote folder. "Test" lists the folder before saving.
class RemoteForm extends StatefulWidget {
  const RemoteForm({super.key, this.existing});
  final RemoteConfig? existing;

  @override
  State<RemoteForm> createState() => _RemoteFormState();
}

class _RemoteFormState extends State<RemoteForm> {
  final _form = GlobalKey<FormState>();
  late RemoteType _type = widget.existing?.type ?? RemoteType.sftp;
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _host = TextEditingController(text: widget.existing?.host);
  late final _port = TextEditingController(
    text: widget.existing?.port?.toString(),
  );
  late final _user = TextEditingController(text: widget.existing?.username);
  late final _password = TextEditingController(text: widget.existing?.password);
  late final _key = TextEditingController(text: widget.existing?.privateKey);
  late final _path = TextEditingController(text: widget.existing?.path ?? '/');
  late final _library = TextEditingController(text: widget.existing?.library);
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    for (final c in [
      _name,
      _host,
      _port,
      _user,
      _password,
      _key,
      _path,
      _library,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  RemoteConfig _build() => RemoteConfig(
    id:
        widget.existing?.id ??
        DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    type: _type,
    name: _name.text.trim().isEmpty ? _host.text.trim() : _name.text.trim(),
    host: _host.text.trim(),
    port: int.tryParse(_port.text.trim()),
    username: _user.text.trim(),
    password: _password.text,
    privateKey: _type == RemoteType.sftp ? _key.text : '',
    path: _path.text.trim().isEmpty ? '/' : _path.text.trim(),
    library: _type == RemoteType.seafile ? _library.text.trim() : '',
  );

  Future<void> _test() async {
    if (!_form.currentState!.validate()) return;
    final c = _build();
    final MediaSource s = switch (c.type) {
      RemoteType.sftp => SftpSource(c),
      RemoteType.webdav => WebDavSource(c),
      RemoteType.seafile => SeafileSource(c),
    };
    setState(() {
      _busy = true;
      _status = 'Connecting…';
    });
    try {
      final path = c.type == RemoteType.webdav
          ? (s as WebDavSource).rootPath
          : c.path;
      final l = await s.list(path).timeout(const Duration(seconds: 30));
      _status =
          'OK: ${l.folders.length} folders, ${l.media.length} photos/videos';
    } catch (e) {
      _status = 'Failed: $e';
    } finally {
      await s.close();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final c = _build();
    await AppScope.read(context).saveRemote(c);
    if (mounted) Navigator.of(context).pop(c);
  }

  @override
  Widget build(BuildContext context) {
    final hostLabel = switch (_type) {
      RemoteType.sftp => 'Host',
      RemoteType.webdav => 'Folder URL (e.g. https://cloud.example.com/remote.php/dav/files/me/Photos)',
      RemoteType.seafile => 'Server URL (e.g. https://seafile.example.com)',
    };
    String? required(String? v) =>
        (v == null || v.trim().isEmpty) ? 'Required' : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Add remote folder' : 'Edit remote folder',
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<RemoteType>(
              segments: [
                for (final t in RemoteType.values)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (optional)'),
            ),
            TextFormField(
              controller: _host,
              validator: required,
              keyboardType: _type == RemoteType.sftp
                  ? TextInputType.text
                  : TextInputType.url,
              decoration: InputDecoration(labelText: hostLabel),
            ),
            if (_type == RemoteType.sftp)
              TextFormField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port',
                  hintText: '22',
                ),
              ),
            TextFormField(
              controller: _user,
              validator: _type == RemoteType.webdav ? null : required,
              decoration: const InputDecoration(labelText: 'User'),
            ),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _type == RemoteType.sftp
                    ? 'Password or key passphrase'
                    : 'Password',
              ),
            ),
            if (_type == RemoteType.sftp)
              TextFormField(
                controller: _key,
                minLines: 2,
                maxLines: 6,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Private key (optional, PEM / OpenSSH)',
                  hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                ),
              ),
            if (_type == RemoteType.seafile)
              TextFormField(
                controller: _library,
                validator: required,
                decoration: const InputDecoration(labelText: 'Library'),
              ),
            if (_type != RemoteType.webdav)
              TextFormField(
                controller: _path,
                decoration: InputDecoration(
                  labelText: _type == RemoteType.seafile
                      ? 'Folder inside the library'
                      : 'Folder',
                  hintText: '/',
                ),
              ),
            const SizedBox(height: 24),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_status!),
              ),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _test,
                  child: const Text('Test'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
