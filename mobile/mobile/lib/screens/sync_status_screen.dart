import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../sync.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  List<Map<String, dynamic>> _actions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await context.read<AppState>().db.allActions();
    setState(() {
      _actions = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync status'),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            icon: const Icon(Icons.sync),
            onPressed: () async {
              await app.runSync();
              await _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Pending: ${app.pendingCount}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_actions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text('No queued actions. Offline score and roster actions appear here.'),
                  )
                else
                  ..._actions.map((a) {
                    final status = a['status']?.toString() ?? 'pending';
                    final type = a['type']?.toString() ?? '';
                    return ListTile(
                      minVerticalPadding: 14,
                      leading: Icon(
                        status == 'pending' ? Icons.hourglass_top : Icons.check_circle_outline,
                        color: status == 'pending'
                            ? const Color(AppState.alphaGold)
                            : Colors.green.shade700,
                      ),
                      title: Text('$type · ${a['action_id']}'),
                      subtitle: Text('Queued ${a['queued_at']} · $status'),
                    );
                  }),
                if (app.lastSyncResults.isNotEmpty) ...[
                  const Divider(),
                  Text('Last sync results', style: Theme.of(context).textTheme.titleMedium),
                  ...app.lastSyncResults.map(
                    (r) => ListTile(
                      title: Text(r['action_id']?.toString() ?? 'action'),
                      subtitle: Text(SyncService.plainResult(r)),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
