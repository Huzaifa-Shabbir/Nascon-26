import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../app_state.dart';

class ClubScreen extends StatefulWidget {
  const ClubScreen({super.key});

  @override
  State<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends State<ClubScreen> {
  late Future<Map<String, dynamic>> _future;
  static const clubId = 'club-alpha-1';

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().loadClub(clubId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Club profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _future = context.read<AppState>().loadClub(clubId);
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(friendlyError(snap.error!), textAlign: TextAlign.center),
              ),
            );
          }
          final c = snap.data ?? {};
          final name = (c['name'] ?? clubId).toString();
          final tenant = (c['tenant_id'] ?? 'tenant-alpha').toString();
          final colors = c['colors'];
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(AppState.alphaBlue), Color(AppState.alphaGold)],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                minVerticalPadding: 12,
                leading: const Icon(Icons.badge),
                title: const Text('Club ID'),
                subtitle: Text((c['club_id'] ?? clubId).toString()),
              ),
              ListTile(
                minVerticalPadding: 12,
                leading: const Icon(Icons.apartment),
                title: const Text('Tenant'),
                subtitle: Text(tenant),
              ),
              if (colors is Map)
                ListTile(
                  minVerticalPadding: 12,
                  leading: const Icon(Icons.palette),
                  title: const Text('Brand colors'),
                  subtitle: Text('Primary ${colors['primary']} · Accent ${colors['accent']}'),
                ),
              const SizedBox(height: 8),
              Text(
                'Cached locally for offline viewing.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}
