import 'package:flutter/material.dart';

import '../core.dart';

class _ClubPage extends StatelessWidget {
  const _ClubPage({
    required this.title,
    this.subtitle,
    this.actions,
    required this.child,
  });
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget child;
  @override
  Widget build(BuildContext context) => PageScaffold(
    title: title,
    subtitle: subtitle,
    actions: actions,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: child,
    ),
  );
}

class ClubScreen extends StatelessWidget {
  const ClubScreen({super.key});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => _ClubPage(
      title: 'Our club.',
      subtitle: 'Good people. Great games.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: brandGradient,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                const TeamBadge(name: 'Alpha Falcons', size: 80),
                const SizedBox(height: 16),
                const Text(
                  'Alpha Falcons',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Islamabad • Alpha Sports',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _heroPill(Icons.verified_outlined, 'Established 2019'),
                    _heroPill(
                      Icons.groups_outlined,
                      '${app.players.where((p) => p.squad == 'Alpha Falcons').length} players',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Built for the team'),
          const SizedBox(height: 10),
          const Text(
            'One club, every kind of athlete. We bring our community together through sport, fair play and a little friendly competition.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Season at a glance'),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(
                child: _ClubStat(value: '12', label: 'Played'),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _ClubStat(value: '8', label: 'Won'),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _ClubStat(value: '26', label: 'Points'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Illustrative 2026 season statistics',
            style: TextStyle(fontSize: 12, color: Color(0xff647455)),
          ),
          const SizedBox(height: 26),
          SectionTitle(
            'The squad',
            action: app.canManage ? 'Manage' : 'View all',
            onAction: () => openPage(context, const RosterScreen()),
          ),
          const SizedBox(height: 10),
          for (final player
              in app.players.where((p) => p.squad == 'Alpha Falcons').take(4))
            _PlayerRow(player: player),
          const SizedBox(height: 24),
          const SectionTitle('At the club'),
          const SizedBox(height: 12),
          const SoftCard(
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Club manager',
                  value: 'Hassan Ali',
                ),
                Divider(height: 24),
                _DetailRow(
                  icon: Icons.sports_outlined,
                  title: 'Head coach',
                  value: 'Sana Ahmed',
                ),
                Divider(height: 24),
                _DetailRow(
                  icon: Icons.location_on_outlined,
                  title: 'Home ground',
                  value: 'FAST Sports Complex, Islamabad',
                ),
                Divider(height: 24),
                _DetailRow(
                  icon: Icons.public_rounded,
                  title: 'Community',
                  value: '@alphafalcons • Alpha Sports',
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          SectionTitle(
            'Club history',
            action: 'See seasons',
            onAction: () => openPage(context, const _SeasonsScreen()),
          ),
          const SizedBox(height: 12),
          const SoftCard(
            child: Row(
              children: [
                Icon(Icons.emoji_events_outlined, size: 38, color: brandInk),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Growing stronger, together',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'A place for every player since 2019.',
                        style: TextStyle(height: 1.5),
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

  Widget _heroPill(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: Colors.white, size: 17),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
    ],
  );
}

class _ClubStat extends StatelessWidget {
  final String value, label;
  const _ClubStat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => SoftCard(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            color: brandInk,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String title, value;
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: brandInk),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Color(0xff647455)),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
            ),
          ],
        ),
      ),
    ],
  );
}

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});
  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  String query = '';
  String filter = 'All';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) {
      final players = app.players
          .where(
            (p) =>
                p.squad == 'Alpha Falcons' &&
                p.name.toLowerCase().contains(query.toLowerCase()) &&
                (filter == 'All' ||
                    (filter == 'On loan'
                        ? p.onLoan
                        : p.role.toLowerCase() == filter.toLowerCase())),
          )
          .toList();
      return _ClubPage(
        title: app.canManage ? 'Your squad.' : 'The squad.',
        subtitle: 'Alpha Falcons • 2026 season',
        actions: app.canManage
            ? [
                IconButton(
                  tooltip: 'Add player',
                  onPressed: () => openPage(context, const _AddPlayerScreen()),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                ),
              ]
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SoftCard(
              child: Row(
                children: [
                  const TeamBadge(name: 'Alpha Falcons', size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Everyone has a part to play.',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${app.players.where((p) => p.squad == 'Alpha Falcons').length} registered players • Demo roster',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                labelText: 'Find a player',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Starter', 'Substitute', 'On loan']
                    .map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f),
                          selected: filter == f,
                          onSelected: (_) => setState(() => filter = f),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
            SectionTitle(
              '${players.length} ${players.length == 1 ? 'player' : 'players'}',
            ),
            const SizedBox(height: 10),
            if (players.isEmpty)
              const SoftCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_search_outlined,
                        size: 38,
                        color: brandInk,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No players found',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Try another name or change the filter.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            for (final player in players) _PlayerRow(player: player),
            if (app.canManage) ...[
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Add a player',
                icon: Icons.person_add_alt_1_outlined,
                onPressed: () => openPage(context, const _AddPlayerScreen()),
              ),
              const SizedBox(height: 28),
              const SectionTitle('Roster activity'),
              const SizedBox(height: 10),
              if (app.rosterHistory.isEmpty)
                const Text(
                  'Your next squad change will appear here. All changes keep an activity record.',
                  style: TextStyle(height: 1.6),
                ),
              for (final entry in app.rosterHistory)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SoftCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 20,
                          color: brandInk,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry,
                            style: const TextStyle(height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

class _PlayerRow extends StatelessWidget {
  final PlayerData player;
  const _PlayerRow({required this.player});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openPage(context, PlayerScreen(player: player)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _PlayerAvatar(player: player),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${player.position} • ${player.onLoan ? 'On loan' : _pretty(player.role)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xff647455),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: brandInk),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PlayerAvatar extends StatelessWidget {
  final PlayerData player;
  final double size;
  const _PlayerAvatar({required this.player, this.size = 46});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: brandCream,
      borderRadius: BorderRadius.circular(size * .35),
    ),
    child: Text(
      player.name
          .split(' ')
          .where((s) => s.isNotEmpty)
          .take(2)
          .map((s) => s[0])
          .join(),
      style: TextStyle(
        color: brandInk,
        fontSize: size * .31,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

String _pretty(String value) => value.isEmpty
    ? value
    : '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}';

class PlayerScreen extends StatelessWidget {
  final PlayerData player;
  const PlayerScreen({super.key, required this.player});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => _ClubPage(
      title: 'Player profile.',
      subtitle: 'The person behind the game',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SoftCard(
            child: Center(
              child: Column(
                children: [
                  _PlayerAvatar(player: player, size: 88),
                  const SizedBox(height: 16),
                  Text(
                    player.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text('${player.position} • ${_pretty(player.role)}'),
                  const SizedBox(height: 12),
                  Chip(
                    avatar: Icon(
                      player.onLoan
                          ? Icons.swap_horiz
                          : Icons.verified_outlined,
                      size: 18,
                    ),
                    label: Text(
                      player.onLoan ? 'On loan' : 'Registered player',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Player details'),
          const SizedBox(height: 12),
          SoftCard(
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.shield_outlined,
                  title: 'Current squad',
                  value: player.squad,
                ),
                const Divider(height: 24),
                _DetailRow(
                  icon: Icons.sports_outlined,
                  title: 'Position',
                  value: player.position,
                ),
                const Divider(height: 24),
                _DetailRow(
                  icon: Icons.badge_outlined,
                  title: 'Squad role',
                  value: _pretty(player.role),
                ),
              ],
            ),
          ),
          if (app.canManage && player.squad == 'Alpha Falcons') ...[
            const SizedBox(height: 28),
            const SectionTitle('Manage player'),
            const SizedBox(height: 10),
            const Text(
              'Transfers move a player as a substitute. Loans return after the selected end date. Every change stays in the club activity record.',
              style: TextStyle(height: 1.6),
            ),
            const SizedBox(height: 16),
            for (final action in [
              ('transfer', Icons.swap_horiz_rounded, 'Transfer player'),
              ('loan', Icons.event_repeat_outlined, 'Loan player'),
              ('release', Icons.person_remove_outlined, 'Release player'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => openPage(
                      context,
                      _RosterActionScreen(player: player, action: action.$1),
                    ),
                    icon: Icon(action.$2),
                    label: Text(action.$3),
                  ),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

class _AddPlayerScreen extends StatefulWidget {
  const _AddPlayerScreen();
  @override
  State<_AddPlayerScreen> createState() => _AddPlayerScreenState();
}

class _AddPlayerScreenState extends State<_AddPlayerScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _position = 'Midfielder', _role = 'substitute';
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _busy || !app.canManage) return;
    setState(() => _busy = true);
    try {
      await app.addPlayer(_name.text.trim(), _position, _role);
      if (!mounted) return;
      message(context, 'Player added to the squad.');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        message(context, error.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _ClubPage(
    title: 'Make room for talent.',
    subtitle: 'Add a player to Alpha Falcons',
    child: !app.canManage
        ? const Text('Only your club manager can add players.')
        : Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SoftCard(
                  child: _DetailRow(
                    icon: Icons.person_add_alt_1_outlined,
                    title: 'A fresh start',
                    value: 'New players join the active club roster.',
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) => (v?.trim().length ?? 0) < 2
                      ? 'Enter a name with at least 2 characters.'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _position,
                  decoration: const InputDecoration(labelText: 'Position'),
                  items:
                      [
                            'Goalkeeper',
                            'Defender',
                            'Midfielder',
                            'Forward',
                            'All-rounder',
                          ]
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => _position = v!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Squad role'),
                  items: ['starter', 'substitute']
                      .map(
                        (r) =>
                            DropdownMenuItem(value: r, child: Text(_pretty(r))),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _role = v!),
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: _busy ? 'Adding player…' : 'Add player',
                  icon: Icons.check_rounded,
                  onPressed: _busy ? null : _save,
                ),
              ],
            ),
          ),
  );
}

class _RosterActionScreen extends StatefulWidget {
  final PlayerData player;
  final String action;
  const _RosterActionScreen({required this.player, required this.action});
  @override
  State<_RosterActionScreen> createState() => _RosterActionScreenState();
}

class _RosterActionScreenState extends State<_RosterActionScreen> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  String _destination = 'Crescent United';
  DateTime? _loanEnd;
  bool _busy = false;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _busy || !app.canManage) return;
    if (widget.action == 'loan' && _loanEnd == null) {
      message(context, 'Choose a loan end date first.');
      return;
    }
    if (widget.player.onLoan) {
      message(
        context,
        'This player is already on loan. Wait for their return before making another move.',
      );
      return;
    }
    final samePosition = app.players
        .where(
          (p) =>
              p.squad == widget.player.squad &&
              p.position == widget.player.position,
        )
        .length;
    if (samePosition <= 1 &&
        widget.player.position.toLowerCase() == 'goalkeeper') {
      message(
        context,
        'Keep at least one goalkeeper in the squad. Add a replacement before moving this player.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_pretty(widget.action)} ${widget.player.name}?'),
        content: Text(
          widget.action == 'release'
              ? 'They will leave Alpha Falcons. Their history will remain in the club activity record.'
              : 'They will ${widget.action == 'loan' ? 'join $_destination on loan until ${_date(_loanEnd!)}' : 'move to $_destination as a substitute'}.${app.online ? '' : ' This action will be queued until you reconnect.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep player'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirm ${widget.action}'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await app.rosterAction(
        widget.player,
        widget.action,
        _destination,
        _reason.text.trim(),
        loanEnd: _loanEnd == null ? null : _date(_loanEnd!),
      );
      if (!mounted) return;
      message(
        context,
        app.online
            ? 'Roster updated. The change is in your activity record.'
            : 'Saved to your pending queue. We will sync when you reconnect.',
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        message(context, error.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => _ClubPage(
    title: '${_pretty(widget.action)} player.',
    subtitle: 'A new chapter for ${widget.player.name}',
    child: !app.canManage
        ? const Text('Only your club manager can change the roster.')
        : Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PlayerRow(player: widget.player),
                const SizedBox(height: 16),
                if (!app.online) ...[
                  const SoftCard(
                    child: _DetailRow(
                      icon: Icons.cloud_off_outlined,
                      title: 'You are offline',
                      value: 'Your change will be saved and checked when you reconnect.',
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (widget.action != 'release') ...[
                  DropdownButtonFormField<String>(
                    initialValue: _destination,
                    decoration: const InputDecoration(
                      labelText: 'Destination squad',
                    ),
                    items: ['Crescent United', 'Alpha Academy']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => setState(() => _destination = v!),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Only squads in Alpha Sports are available.',
                    style: TextStyle(fontSize: 12, color: Color(0xff647455)),
                  ),
                  const SizedBox(height: 20),
                ],
                if (widget.action == 'loan') ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        _loanEnd == null
                            ? 'Choose loan end date'
                            : 'Ends ${_date(_loanEnd!)}',
                      ),
                      onPressed: () async {
                        final now = DateTime.now();
                        final date = await showDatePicker(
                          context: context,
                          initialDate:
                              _loanEnd ?? now.add(const Duration(days: 30)),
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: now.add(const Duration(days: 730)),
                        );
                        if (date != null && mounted) {
                          setState(() => _loanEnd = date);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The player returns the day after this date.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                ],
                TextFormField(
                  controller: _reason,
                  maxLines: 3,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: 'Reason for this change',
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v?.trim().length ?? 0) < 5
                      ? 'Add a short reason with at least 5 characters.'
                      : null,
                ),
                const SizedBox(height: 10),
                Text(
                  widget.action == 'release'
                      ? 'Releases are available throughout the season.'
                      : 'Demo transfer window: 1–31 October 2026, including both dates. Changes during a live match take effect after it ends.',
                  style: const TextStyle(height: 1.6, color: Color(0xff647455)),
                ),
                const SizedBox(height: 26),
                PrimaryButton(
                  label: _busy ? 'Saving change…' : 'Review ${widget.action}',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _busy ? null : _submit,
                ),
              ],
            ),
          ),
  );
}

class _SeasonsScreen extends StatelessWidget {
  const _SeasonsScreen();
  @override
  Widget build(BuildContext context) => _ClubPage(
    title: 'A club in motion.',
    subtitle: 'Alpha Falcons • Illustrative history',
    child: Column(
      children: [
        for (final s in [
          (
            '2026',
            'The season is ours to write',
            '8 wins • 26 points • In progress',
          ),
          ('2025', 'A year of progress', 'League runners-up • 11 wins'),
          ('2024', 'Stronger as a squad', 'Semifinalists • 9 wins'),
          ('2019', 'Our first whistle', 'Alpha Falcons founded in Islamabad'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: SoftCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.$1,
                    style: const TextStyle(
                      fontSize: 22,
                      color: brandInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.$2,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(s.$3, style: const TextStyle(height: 1.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
