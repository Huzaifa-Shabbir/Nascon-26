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

  int _sideScore(dynamic side) {
    if (side is Map && side['score'] != null) {
      final s = side['score'];
      if (s is num) return s.toInt();
    }
    return 0;
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
                    Text(
                      '${widget.home} vs ${widget.away}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: () => setState(_reload),
                        child: const Text('Retry'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snap.data ?? {};
          final homeScore = _sideScore(data['home']);
          final awayScore = _sideScore(data['away']);
          final homeId = (data['home'] is Map ? data['home']['team_id'] : null) ?? widget.home;
          final awayId = (data['away'] is Map ? data['away']['team_id'] : null) ?? widget.away;
          final outcome = (data['outcome'] ?? 'pending').toString();
          final status = (data['status'] ?? '').toString();
          final version = data['version'];
          final timeline = (data['events'] is List) ? data['events'] as List : const [];

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
                        '$homeId  $homeScore  –  $awayScore  $awayId',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text('Status: $status · Outcome: $outcome'),
                      if (version != null) Text('Version: $version'),
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
                  child: Text('No events yet.'),
                )
              else
                ...timeline.map((e) {
                  final m = e is Map ? e : <String, dynamic>{};
                  final type = (m['type'] ?? 'event').toString();
                  final id = (m['event_id'] ?? '').toString();
                  final seq = m['sequence'];
                  final compensated = m['compensated'] == true;
                  final payload = m['payload'];
                  String detail = '';
                  if (payload is Map) {
                    final et = payload['event_type'];
                    final team = payload['team_id'];
                    if (et != null || team != null) {
                      detail = [if (team != null) '$team', if (et != null) '$et'].join(' · ');
                    }
                  }
                  return ListTile(
                    minVerticalPadding: 12,
                    leading: Icon(
                      compensated ? Icons.undo : Icons.sports,
                      color: compensated ? Colors.orange : null,
                    ),
                    title: Text(compensated ? '$type (compensated)' : type),
                    subtitle: Text(
                      [
                        if (id.isNotEmpty) id,
                        if (seq != null) 'seq $seq',
                        if (detail.isNotEmpty) detail,
                      ].join(' · '),
                    ),
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
                subtitle: const Text('Alpha United Home Jersey — see Store'),
              ),
            ],
          );
        },
      ),
    );
  }
}
