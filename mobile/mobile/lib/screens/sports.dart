import 'package:flutter/material.dart';

import '../core.dart';
import 'store.dart';

const _sports = ['All sports', 'Football', 'Basketball', 'Cricket', 'Esports'];

class _SportsScaffold extends StatelessWidget {
  const _SportsScaffold({
    required this.title,
    this.subtitle,
    required this.child,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => PageScaffold(
    title: title,
    subtitle: subtitle,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: child,
    ),
  );
}

class FixturesScreen extends StatefulWidget {
  const FixturesScreen({super.key});
  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen> {
  String sport = 'All sports', status = 'All', query = '', day = 'All dates';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final filtered = app.matches
          .where(
            (m) =>
                (sport == 'All sports' ||
                    m.sport.toLowerCase() == sport.toLowerCase()) &&
                (status == 'All' ||
                    m.status.toLowerCase() == status.toLowerCase()) &&
                ('${m.home} ${m.away} ${m.venue}'.toLowerCase().contains(
                  query.toLowerCase(),
                )) &&
                (day == 'All dates' || m.day == day),
          )
          .toList();
      return _SportsScaffold(
        title: 'Fixtures',
        subtitle: 'Find your next courtside moment.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search teams or venues',
              ),
            ),
            const SizedBox(height: 16),
            _chips(_sports, sport, (v) => setState(() => sport = v)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _select(status, [
                    'All',
                    'Live',
                    'Upcoming',
                    'Completed',
                  ], (v) => setState(() => status = v)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _select(day, [
                    'All dates',
                    'Today',
                    'Tomorrow',
                  ], (v) => setState(() => day = v)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SectionTitle(
              '${filtered.length} matches',
              action: 'Schedule',
              onAction: () => _schedule(context),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              _empty(
                'No matches found',
                'Try another sport, date or team name.',
                Icons.event_busy_rounded,
              ),
            for (final match in filtered)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MatchTile(match: match),
              ),
            const SizedBox(height: 8),
            const Text(
              'Demo fixtures · Available offline',
              style: TextStyle(color: Color(0xff647153), fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
  void _schedule(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The weekend lineup',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('17–18 October 2026 · Alpha Sports'),
            const SizedBox(height: 20),
            for (final m in app.matches)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: Text('${m.home} vs ${m.away}'),
                subtitle: Text('${m.time} · ${m.venue}'),
                onTap: () {
                  Navigator.pop(context);
                  openPage(context, MatchDetailScreen(match: m));
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class MatchTile extends StatelessWidget {
  final MatchData match;
  const MatchTile({super.key, required this.match});
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${match.home} versus ${match.away}, ${match.status}',
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openPage(context, MatchDetailScreen(match: match)),
      child: SoftCard(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.sport,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xff647153),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _status(match.status),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _team(match.home)),
                Text(
                  match.status.toLowerCase() == 'upcoming'
                      ? 'VS'
                      : '${match.homeScore} : ${match.awayScore}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: brandInk,
                  ),
                ),
                Expanded(child: _team(match.away)),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 15,
                  color: Color(0xff647153),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    match.venue,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xff647153),
                    ),
                  ),
                ),
                Text(
                  match.time,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class MatchDetailScreen extends StatelessWidget {
  final MatchData match;
  const MatchDetailScreen({super.key, required this.match});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => _SportsScaffold(
      title: 'Match centre',
      subtitle: '${match.sport} · Alpha League',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            decoration: BoxDecoration(
              gradient: brandGradient,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                _status(match.status),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _team(match.home, large: true)),
                    Text(
                      '${match.homeScore} : ${match.awayScore}',
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    Expanded(child: _team(match.away, large: true)),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  '${match.time} · ${match.venue}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  app.online
                      ? 'Demo live updates enabled'
                      : 'Offline · Showing saved match',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
          if (app.canScore && match.status.toLowerCase() != 'completed') ...[
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Open scoring desk',
              icon: Icons.edit_note_rounded,
              onPressed: () => openPage(context, ScoringScreen(match: match)),
            ),
          ],
          const SizedBox(height: 28),
          SectionTitle('Match timeline'),
          const SizedBox(height: 12),
          if (match.events.isEmpty)
            _empty(
              'The story starts soon',
              'Every scoring moment will appear here.',
              Icons.sports_score_rounded,
            ),
          for (final event in match.events.reversed) _eventRow(event),
          const SizedBox(height: 24),
          SectionTitle('Wear your colours'),
          const SizedBox(height: 12),
          SoftCard(
            child: Row(
              children: [
                Container(
                  width: 68,
                  height: 76,
                  decoration: BoxDecoration(
                    color: brandCream,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.checkroom_rounded,
                    color: brandInk,
                    size: 44,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Alpha home jersey',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Official club collection',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xff647153),
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'PKR 4,500',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextButton(
                        onPressed: () => _product(context),
                        child: const Text('View jersey →'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  void _product(BuildContext context) =>
      openPage(context, ProductScreen(product: app.products.first));
}

class ScoringScreen extends StatefulWidget {
  final MatchData match;
  const ScoringScreen({super.key, required this.match});
  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  late String team = widget.match.home;
  late String event = widget.match.scoringOptions.keys.first;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final m = widget.match;
      return _SportsScaffold(
        title: 'Scoring desk',
        subtitle: '${m.home} vs ${m.away}',
        child: !app.canScore
            ? _empty(
                'Organizer access required',
                'Sign in with an organizer account to record match events.',
                Icons.lock_outline_rounded,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SoftCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            m.home,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${m.homeScore} : ${m.awayScore}',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: brandInk,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            m.away,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (m.status.toLowerCase() == 'completed')
                    _empty(
                      'Match completed',
                      'The final score is saved. Review the event history below.',
                      Icons.check_circle_outline_rounded,
                    )
                  else ...[
                    SectionTitle('Record a moment'),
                    const SizedBox(height: 12),
                    _select(team, [
                      m.home,
                      m.away,
                    ], (v) => setState(() => team = v)),
                    const SizedBox(height: 12),
                    _select(
                      event,
                      m.scoringOptions.keys.toList(),
                      (v) => setState(() => event = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        '${m.scoringOptions[event]} points · Event value from this sport’s configuration',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xff647153),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: app.online ? 'Save event' : 'Queue event offline',
                      icon: app.online
                          ? Icons.add_rounded
                          : Icons.cloud_upload_outlined,
                      onPressed: () {
                        app.addScore(m, team, event, m.scoringOptions[event]!);
                        message(
                          context,
                          app.online ? 'Event recorded. Score updated.' : 'Event saved on this device and queued for sync.',
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _finish(context),
                      child: const Text('Finish match'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SectionTitle('Event history'),
                  const SizedBox(height: 6),
                  const Text(
                    'Corrections preserve the original event for a clear audit trail.',
                    style: TextStyle(fontSize: 13, color: Color(0xff647153)),
                  ),
                  const SizedBox(height: 14),
                  if (m.events.isEmpty)
                    _empty(
                      'No events yet',
                      'Select a team and save the first event.',
                      Icons.edit_note_rounded,
                    ),
                  for (final e in m.events.reversed)
                    Column(
                      children: [
                        _eventRow(e),
                        if (!e.compensated &&
                            m.status.toLowerCase() != 'completed')
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _correct(context, e),
                              icon: const Icon(Icons.undo_rounded, size: 18),
                              label: const Text('Correct event'),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
      );
    },
  );
  Future<void> _correct(BuildContext context, ScoreEntry entry) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct this event?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${entry.team} · ${entry.label}\nThe original stays in the timeline. Its effect will be reversed.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Reason for correction',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep event'),
          ),
          TextButton(
            onPressed: () {
              if (reason.text.trim().isEmpty) {
                message(context, 'Add a reason so the correction is clear.');
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Confirm correction'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      app.compensate(widget.match, entry, reason: reason.text.trim());
      message(
        context,
        app.online
            ? 'Event corrected. The score has been recalculated.'
            : 'Correction queued for sync.',
      );
    }
    reason.dispose();
  }

  Future<void> _finish(BuildContext context) async {
    if (!app.online) {
      message(
        context,
        'Reconnect before making the score final. Scoring events can still be queued offline.',
      );
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make this score final?'),
        content: Text(
          '${widget.match.home} ${widget.match.homeScore} : ${widget.match.awayScore} ${widget.match.away}\nYou will no longer be able to add events.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep scoring'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finish match'),
          ),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      app.finishMatch(widget.match);
      message(context, 'Match completed. Final score saved.');
    }
  }
}

class StandingsScreen extends StatefulWidget {
  const StandingsScreen({super.key});
  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> {
  String sport = 'Football', league = 'Alpha Premier League';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final fixtures = app.matches
          .where((m) => m.sport.toLowerCase() == sport.toLowerCase())
          .toList();
      final names = fixtures.expand((m) => [m.home, m.away]).toSet().toList();
      final rows =
          names.map((name) {
            final row = _Standing(name);
            for (final m in fixtures.where(
              (m) => m.home == name || m.away == name,
            )) {
              if (m.status.toLowerCase() != 'completed') {
                row.remaining++;
                continue;
              }
              row.played++;
              final scored = m.home == name ? m.homeScore : m.awayScore;
              final conceded = m.home == name ? m.awayScore : m.homeScore;
              row.scored += scored;
              row.diff += scored - conceded;
              final outcome = scored > conceded
                  ? 'W'
                  : scored == conceded
                  ? 'D'
                  : 'L';
              row.form.add(outcome);
              row.points += outcome == 'W'
                  ? 3
                  : outcome == 'D'
                  ? 1
                  : 0;
            }
            return row;
          }).toList()..sort((a, b) {
            final points = b.points.compareTo(a.points);
            if (points != 0) return points;
            final diff = b.diff.compareTo(a.diff);
            return diff != 0 ? diff : a.name.compareTo(b.name);
          });
      for (final row in rows) {
        final others = rows.where((r) => r != row);
        row.status =
            others
                    .where((r) => r.points + r.remaining * 3 >= row.points)
                    .length <
                2
            ? 'Qualified'
            : others
                      .where((r) => r.points > row.points + row.remaining * 3)
                      .length >=
                  2
            ? 'Eliminated'
            : 'In contention';
      }
      return _SportsScaffold(
        title: 'Standings',
        subtitle: 'Every point moves the story.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _select(league, [
              'Alpha Premier League',
            ], (v) => setState(() => league = v)),
            const SizedBox(height: 16),
            _chips(
              _sports.skip(1).toList(),
              sport,
              (v) => setState(() => sport = v),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: brandGradient,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.emoji_events_outlined,
                    color: Colors.white,
                    size: 30,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    league,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$sport · Top 2 advance to the finals',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionTitle('League table'),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  SizedBox(width: 28, child: Text('#')),
                  Expanded(child: Text('Club')),
                  SizedBox(
                    width: 30,
                    child: Text('P', textAlign: TextAlign.center),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text('Pts', textAlign: TextAlign.end),
                  ),
                ],
              ),
            ),
            for (final entry in rows.asMap().entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _teamDetail(context, entry.value),
                  child: SoftCard(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${entry.key + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TeamBadge(name: entry.value.name, size: 32),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.value.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                entry.value.status,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xff526335),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 30,
                          child: Text(
                            '${entry.value.played}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${entry.value.points}',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: brandInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Qualification is shown with words as well as colour. Tap a club for its form and head-to-head results.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xff647153),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Demo league rules: win 3 points, draw 1. Table updates from completed matches and is available offline.',
              style: TextStyle(fontSize: 11, color: Color(0xff647153)),
            ),
          ],
        ),
      );
    },
  );
  void _teamDetail(
    BuildContext context,
    _Standing row,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TeamBadge(name: row.name, size: 56),
            const SizedBox(height: 16),
            Text(row.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('${row.points} points · ${row.status}'),
            const SizedBox(height: 8),
            Text(
              '${row.played} played · ${row.scored} scored · ${row.diff >= 0 ? '+' : ''}${row.diff} difference',
            ),
            const SizedBox(height: 24),
            const Text(
              'Recent form',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: row.form
                  .map(
                    (f) => Chip(
                      label: Text(f),
                      backgroundColor: f == 'W'
                          ? brandGreen.withValues(alpha: .25)
                          : brandCream,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            const Text(
              'Head to head',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final m in app.matches.where(
              (m) => m.home == row.name || m.away == row.name,
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${m.home} vs ${m.away}'),
                subtitle: Text('${m.sport} · ${m.status}'),
                trailing: Text(
                  '${m.homeScore} : ${m.awayScore}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.pop(context);
                  openPage(context, MatchDetailScreen(match: m));
                },
              ),
            const SizedBox(height: 16),
            const Text(
                  'Demo ties use score difference, then club name. Qualification reflects the remaining demo fixtures.',
              style: TextStyle(color: Color(0xff647153), fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Standing {
  final String name;
  String status = 'In contention';
  int played = 0, points = 0, scored = 0, diff = 0, remaining = 0;
  final List<String> form = [];
  _Standing(this.name);
}

Widget _select(
  String selected,
  List<String> options,
  ValueChanged<String> change,
) => DropdownButtonFormField<String>(
  initialValue: selected,
  isExpanded: true,
  decoration: const InputDecoration(
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  ),
  items: options
      .map(
        (v) => DropdownMenuItem(
          value: v,
          child: Text(
            v,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      )
      .toList(),
  onChanged: (v) {
    if (v != null) change(v);
  },
);
Widget _chips(
  List<String> values,
  String selected,
  ValueChanged<String> change,
) => SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    children: values
        .map(
          (v) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(v),
              selected: selected == v,
              onSelected: (_) => change(v),
              showCheckmark: false,
              selectedColor: brandGreen,
              labelStyle: TextStyle(
                color: brandInk,
                fontWeight: selected == v ? FontWeight.w700 : FontWeight.w500,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            ),
          ),
        )
        .toList(),
  ),
);
Widget _team(String name, {bool large = false}) => Column(
  children: [
    TeamBadge(name: name, size: large ? 56 : 42),
    const SizedBox(height: 9),
    Text(
      name,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: large ? 12 : 12,
        fontWeight: FontWeight.w700,
        color: large ? Colors.white : brandInk,
      ),
    ),
  ],
);
Widget _status(String status) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(
    color: status.toLowerCase() == 'live'
        ? const Color(0xffe8f6d6)
        : brandCream,
    borderRadius: BorderRadius.circular(30),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        status.toLowerCase() == 'live'
            ? Icons.sensors_rounded
            : status.toLowerCase() == 'completed'
            ? Icons.check_circle_outline_rounded
            : Icons.schedule_rounded,
        size: 13,
        color: brandInk,
      ),
      const SizedBox(width: 4),
      Text(
        status,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: brandInk,
        ),
      ),
    ],
  ),
);
Widget _eventRow(ScoreEntry event) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 10),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: brandGreen.withValues(alpha: .18),
          shape: BoxShape.circle,
        ),
        child: Icon(
          event.compensated ? Icons.undo_rounded : Icons.sports_score_rounded,
          size: 19,
          color: brandInk,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                decoration: event.compensated
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              event.compensated ? '${event.team} · Corrected' : event.team,
              style: const TextStyle(fontSize: 12, color: Color(0xff647153)),
            ),
          ],
        ),
      ),
      Text(
        event.compensated ? 'Reversed' : '+${event.points}',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: brandInk,
        ),
      ),
    ],
  ),
);
Widget _empty(String title, String subtitle, IconData icon) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 30),
  child: Center(
    child: Column(
      children: [
        Icon(icon, size: 42, color: brandInk),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xff647153), height: 1.5),
        ),
      ],
    ),
  ),
);
