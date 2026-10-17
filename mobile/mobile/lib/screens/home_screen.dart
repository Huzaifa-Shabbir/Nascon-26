import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'club_screen.dart';
import 'fixtures_screen.dart';
import 'roster_screen.dart';
import 'scoring_screen.dart';
import 'settings_screen.dart';
import 'standings_screen.dart';
import 'store_screen.dart';
import 'sync_status_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tiles = <_Tile>[
      _Tile('Fixtures', Icons.sports_soccer, () => const FixturesScreen()),
      _Tile('Standings', Icons.leaderboard, () => const StandingsScreen()),
      _Tile('Club', Icons.groups, () => const ClubScreen()),
      _Tile('Store', Icons.storefront, () => const StoreScreen()),
      if (app.canManageRoster)
        _Tile('Roster', Icons.swap_horiz, () => const RosterScreen()),
      if (app.canScore)
        _Tile('Scoring', Icons.edit_note, () => const ScoringScreen()),
      _Tile('Sync queue', Icons.cloud_sync, () => const SyncStatusScreen()),
      _Tile('Settings', Icons.settings, () => const SettingsScreen()),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alpha Sports'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => app.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Welcome, ${app.roleLabel()}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(app.email ?? '', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          ...tiles.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                minVerticalPadding: 16,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                leading: Icon(t.icon, color: const Color(AppState.alphaBlue)),
                title: Text(t.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => t.builder()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile {
  _Tile(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final Widget Function() builder;
}
