import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../app_state.dart';
import 'match_detail_screen.dart';

class FixturesScreen extends StatefulWidget {
  const FixturesScreen({super.key});

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().loadMatches(leagueId: AppState.demoLeagueId);
  }

  void _reload() {
    setState(() {
      _future = context.read<AppState>().loadMatches(leagueId: AppState.demoLeagueId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fixtures'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
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
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const Center(child: Text('No fixtures yet for this league.'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = items[i] as Map;
              final matchId = (m['match_id'] ?? '').toString();
              final home = (m['home_team_id'] ?? m['home'] ?? '?').toString();
              final away = (m['away_team_id'] ?? m['away'] ?? '?').toString();
              final status = (m['status'] ?? 'upcoming').toString();
              final hs = m['home_score'];
              final as_ = m['away_score'];
              final scoreLine = (hs != null && as_ != null) ? ' · $hs–$as_' : '';
              return ListTile(
                minVerticalPadding: 16,
                title: Text('$home vs $away'),
                subtitle: Text('$matchId · $status$scoreLine'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MatchDetailScreen(
                      matchId: matchId,
                      home: home,
                      away: away,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
