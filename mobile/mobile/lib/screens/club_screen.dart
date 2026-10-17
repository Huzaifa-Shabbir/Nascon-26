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
  late String _clubId;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _clubId = app.effectiveClubId;
    _future = app.loadClub(_clubId);
  }

  void _reload() {
    setState(() {
      _future = context.read<AppState>().loadClub(_clubId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Club profile'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(friendlyError(snap.error!), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: FilledButton(onPressed: _reload, child: const Text('Retry')),
                    ),
                  ],
                ),
              ),
            );
          }
          final c = snap.data ?? {};
          final name = (c['name'] ?? _clubId).toString();
          final tenant = c['tenant'] is Map ? c['tenant'] as Map : null;
          final branding = tenant?['branding'] is Map ? tenant!['branding'] as Map : null;
          final profile = c['profile'] is Map ? c['profile'] as Map : null;
          final venue = profile?['home_venue'] is Map ? profile!['home_venue'] as Map : null;
          final staff = profile?['staff'] is Map ? profile!['staff'] as Map : null;
          final players = (c['players'] is List) ? c['players'] as List : const [];

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
                subtitle: Text((c['club_id'] ?? _clubId).toString()),
              ),
              ListTile(
                minVerticalPadding: 12,
                leading: const Icon(Icons.apartment),
                title: const Text('Tenant'),
                subtitle: Text(
                  '${tenant?['name'] ?? c['tenant_id'] ?? '—'}'
                  '${branding != null ? ' · ${branding['primary_color']}' : ''}',
                ),
              ),
              if (venue != null)
                ListTile(
                  minVerticalPadding: 12,
                  leading: const Icon(Icons.stadium),
                  title: const Text('Home venue'),
                  subtitle: Text('${venue['name'] ?? '—'}'),
                ),
              if (staff != null) ...[
                const SizedBox(height: 8),
                Text('Staff', style: Theme.of(context).textTheme.titleMedium),
                for (final e in staff.entries)
                  ListTile(
                    minVerticalPadding: 8,
                    title: Text(e.key.toString()),
                    subtitle: Text('${e.value}'),
                  ),
              ],
              const SizedBox(height: 8),
              Text('Roster', style: Theme.of(context).textTheme.titleMedium),
              if (players.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No players listed for this club.'),
                )
              else
                for (final p in players)
                  if (p is Map)
                    ListTile(
                      minVerticalPadding: 8,
                      title: Text((p['name'] ?? p['player_id'] ?? '').toString()),
                      subtitle: Text('${p['player_id']} · ${p['position'] ?? '—'}'),
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
