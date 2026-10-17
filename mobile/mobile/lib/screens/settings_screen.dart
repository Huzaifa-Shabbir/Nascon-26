import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _url;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: context.read<AppState>().baseUrl);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Server URL', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              hintText: 'http://10.0.2.2:8080',
              helperText: 'Emulator: 10.0.2.2:8080 · Device: laptop LAN IP:8080',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () async {
                await app.setBaseUrl(_url.text);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Server URL saved')),
                  );
                }
              },
              child: const Text('Save URL'),
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Device ID'),
            subtitle: Text(app.deviceId),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Quick presets'),
            subtitle: const Text('Tap to fill'),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _url.text = 'http://10.0.2.2:8080'),
                child: const Text('Emulator'),
              ),
              OutlinedButton(
                onPressed: () => setState(() => _url.text = 'http://192.168.1.1:8080'),
                child: const Text('LAN sample'),
              ),
              OutlinedButton(
                onPressed: () => setState(() => _url.text = 'http://127.0.0.1:8080'),
                child: const Text('Localhost'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
