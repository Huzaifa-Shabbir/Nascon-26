import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../app_state.dart';

class StandingsScreen extends StatefulWidget {
  const StandingsScreen({super.key});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().loadStandings(AppState.demoLeagueId);
  }

  void _reload() {
    setState(() {
      _future = context.read<AppState>().loadStandings(AppState.demoLeagueId);
    });
  }

  Color? _qualColor(String? status) {
    switch (status) {
      case 'clinched':
        return Colors.green.shade700;
      case 'eliminated':
        return Colors.red.shade700;
      case 'still_possible':
        return const Color(AppState.alphaGold);
      default:
        return null;
    }
  }

  String _qualLabel(String? status) {
    switch (status) {
      case 'clinched':
        return 'Clinched';
      case 'eliminated':
        return 'Eliminated';
      case 'still_possible':
        return 'Still possible';
      default:
        return status ?? '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Standings'),
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
          final data = snap.data ?? {};
          final table = (data['table'] is List) ? data['table'] as List : const [];
          if (table.isEmpty) {
            return const Center(
              child: Text('No standings yet. Complete matches to fill the table.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                'League: ${data['league_id'] ?? AppState.demoLeagueId}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (data['qualification_spots'] != null)
                Text('Qualification spots: ${data['qualification_spots']}'),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('Team')),
                    DataColumn(label: Text('Pts')),
                    DataColumn(label: Text('P')),
                    DataColumn(label: Text('GD')),
                    DataColumn(label: Text('Qual')),
                  ],
                  rows: [
                    for (var i = 0; i < table.length; i++)
                      () {
                        final row = table[i] is Map ? table[i] as Map : {};
                        final team = (row['team_id'] ?? 'T$i').toString();
                        final pts = row['points'] ?? 0;
                        final played = row['played'] ?? 0;
                        final diff = row['diff'] ?? 0;
                        final qual = row['status']?.toString();
                        return DataRow(cells: [
                          DataCell(Text('${row['rank'] ?? i + 1}')),
                          DataCell(Text(team)),
                          DataCell(Text('$pts')),
                          DataCell(Text('$played')),
                          DataCell(Text('$diff')),
                          DataCell(Text(
                            _qualLabel(qual),
                            style: TextStyle(
                              color: _qualColor(qual),
                              fontWeight: FontWeight.w600,
                            ),
                          )),
                        ]);
                      }(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
