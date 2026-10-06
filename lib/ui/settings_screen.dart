import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/cache.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<int> _cacheSize = MediaCache.instance.sizeBytes();

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Grid columns'),
            subtitle: Slider(
              value: app.columns.toDouble(),
              min: 2,
              max: 8,
              divisions: 6,
              label: '${app.columns}',
              onChanged: (v) => app.columns = v.round(),
            ),
            trailing: Text(
              '${app.columns}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SwitchListTile(
            title: const Text('Autoplay videos'),
            value: app.autoplayVideos,
            onChanged: (v) => app.autoplayVideos = v,
          ),
          ListTile(
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: app.themeMode,
              onChanged: (v) => app.themeMode = v!,
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              ],
            ),
          ),
          FutureBuilder<int>(
            future: _cacheSize,
            builder: (context, snap) => ListTile(
              title: const Text('Remote files cache'),
              subtitle: Text(snap.hasData ? _mb(snap.data!) : '…'),
              trailing: TextButton(
                onPressed: () async {
                  await MediaCache.instance.clear();
                  setState(() => _cacheSize = MediaCache.instance.sizeBytes());
                },
                child: const Text('Clear'),
              ),
            ),
          ),
          const AboutListTile(
            applicationName: 'Gallery',
            applicationLegalese: 'MIT License',
            icon: Icon(Icons.info_outline),
          ),
        ],
      ),
    );
  }
}
