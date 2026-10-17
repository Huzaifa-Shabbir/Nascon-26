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
  static const leagueId = 'league-alpha-1';

  @override
  void initState() {
    super.initState();
    _future = context.read<AppState>().loadStandings(leagueId);
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _future = context.read<AppState>().loadStandings(leagueId);
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
          final data = snap.data ?? {};
          final table = (data['table'] ?? data['standings'] ?? data['teams'] ?? []) as List? ?? [];
          if (table.isEmpty) {
            return const Center(
              child: Text('No standings yet. Register a league and complete matches first.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text('League: $leagueId', style: Theme.of(context).textTheme.titleSmall),
              if (data['resolved_by'] != null)
                Text('Resolved by: ${data['resolved_by']}'),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('Team')),
                    DataColumn(label: Text('Pts')),
                    DataColumn(label: Text('P')),
                    DataColumn(label: Text('Qual')),
                  ],
                  rows: [
                    for (var i = 0; i < table.length; i++)
                      () {
                        final row = table[i] is Map ? table[i] as Map : {};
                        final team = (row['team_id'] ?? row['team'] ?? row['name'] ?? 'T$i').toString();
                        final pts = row['points'] ?? row['pts'] ?? 0;
                        final played = row['played'] ?? row['p'] ?? 0;
                        final qual = (row['qualification'] ?? row['status'] ?? row['qual']).toString();
                        return DataRow(cells: [
                          DataCell(Text('${row['rank'] ?? i + 1}')),
                          DataCell(Text(team)),
                          DataCell(Text('$pts')),
                          DataCell(Text('$played')),
                          DataCell(Text(
                            _qualLabel(qual == 'null' ? null : qual),
                            style: TextStyle(
                              color: _qualColor(qual == 'null' ? null : qual),
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
