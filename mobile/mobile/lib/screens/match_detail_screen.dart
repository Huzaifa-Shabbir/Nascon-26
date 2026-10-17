import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../app_state.dart';

class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({
    super.key,
    required this.matchId,
    required this.home,
    required this.away,
  });

  final String matchId;
  final String home;
  final String away;

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = context.read<AppState>().loadScore(widget.matchId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.matchId),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_reload),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(friendlyError(snap.error!), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Text('${widget.home} vs ${widget.away}', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text('Score not available yet. Match may still be upcoming.'),
                  ],
                ),
              ),
            );
          }
          final data = snap.data ?? {};
          final homeScore = data['home_score'] ?? data['score']?['home'] ?? 0;
          final awayScore = data['away_score'] ?? data['score']?['away'] ?? 0;
          final outcome = (data['outcome'] ?? 'pending').toString();
          final timeline = (data['timeline'] ?? data['events'] ?? data['log'] ?? []) as List? ?? [];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: const Color(AppState.alphaBlue).withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        '${widget.home}  $homeScore  –  $awayScore  ${widget.away}',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text('Outcome: $outcome'),
                      if (data['match_version'] != null)
                        Text('Version: ${data['match_version']}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Event timeline', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (timeline.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No events yet. Scores appear after match_init / score events.'),
                )
              else
                ...timeline.map((e) {
                  final m = e is Map ? e : <String, dynamic>{};
                  final type = (m['type'] ?? m['event_type'] ?? m['payload']?['event_type'] ?? 'event').toString();
                  final id = (m['event_id'] ?? m['id'] ?? '').toString();
                  final seq = m['sequence'];
                  return ListTile(
                    minVerticalPadding: 12,
                    leading: const Icon(Icons.sports),
                    title: Text(type),
                    subtitle: Text([if (id.isNotEmpty) id, if (seq != null) 'seq $seq'].join(' · ')),
                  );
                }),
              const SizedBox(height: 16),
              ListTile(
                minVerticalPadding: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                leading: const Icon(Icons.shopping_bag, color: Color(AppState.alphaGold)),
                title: const Text('Pinned product'),
                subtitle: const Text('Alpha Home Jersey (M) — PKR 4500.00'),
              ),
            ],
          );
        },
      ),
    );
  }
}
