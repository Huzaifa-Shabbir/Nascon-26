import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import '../app_state.dart';

class ScoringScreen extends StatefulWidget {
  const ScoringScreen({super.key});

  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  final _matchId = TextEditingController(text: 'm-demo-1');
  final _teamId = TextEditingController(text: 't1');
  final _eventType = TextEditingController(text: 'goal');
  final _targetEvent = TextEditingController();
  final _reason = TextEditingController(text: 'VAR review');
  bool _compensation = false;
  bool _busy = false;
  String? _message;
  int _baseVersion = 0;

  Future<void> _refreshVersion(AppState app) async {
    try {
      final score = await app.loadScore(_matchId.text.trim());
      final v = score['version'];
      if (v is int && mounted) setState(() => _baseVersion = v);
    } catch (_) {
      // leave base version as-is
    }
  }

  Future<void> _ensureStarted(AppState app) async {
    final mid = _matchId.text.trim();
    try {
      final score = await app.loadScore(mid);
      if (score['status'] == 'upcoming') {
        await app.submitScoreEvent({
          'event_id': 'start-${const Uuid().v4().substring(0, 8)}',
          'match_id': mid,
          'type': 'match_start',
          'payload': {},
        }, baseVersion: score['version'] is int ? score['version'] as int : 0);
      }
    } catch (_) {
      // If match missing, user must open Fixtures first (creates demo league).
    }
  }

  Future<void> _submit() async {
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _message = null;
    });
    final eventId = 'evt-${const Uuid().v4().substring(0, 12)}';
    await _ensureStarted(app);
    await _refreshVersion(app);

    final Map<String, dynamic> payload;
    if (_compensation) {
      payload = {
        'event_id': eventId,
        'match_id': _matchId.text.trim(),
        'type': 'compensation',
        'payload': {
          'compensates': _targetEvent.text.trim(),
          'reason': _reason.text.trim().isEmpty ? 'Correction' : _reason.text.trim(),
        },
      };
    } else {
      payload = {
        'event_id': eventId,
        'match_id': _matchId.text.trim(),
        'type': 'score',
        'payload': {
          'team_id': _teamId.text.trim(),
          'event_type': _eventType.text.trim(),
        },
      };
    }

    try {
      final result = await app.submitScoreEvent(
        payload,
        baseVersion: _baseVersion,
      );
      if (!mounted) return;
      setState(() {
        if (result['queued'] == true) {
          _message = 'Saved offline. Open Sync queue to watch it sync.';
        } else {
          _message =
              'Event applied. sequence=${result['sequence'] ?? '—'} version=${result['match_version'] ?? '—'}';
          if (result['match_version'] is int) {
            _baseVersion = result['match_version'] as int;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _matchId.dispose();
    _teamId.dispose();
    _eventType.dispose();
    _targetEvent.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scoring entry'),
        actions: [
          IconButton(
            tooltip: 'Refresh match version',
            onPressed: () => _refreshVersion(context.read<AppState>()),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Uses POST /audit/v1/events. Open Fixtures first so demo matches exist '
            '(default m-demo-1, teams t1/t2).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Compensation event'),
            value: _compensation,
            onChanged: (v) => setState(() => _compensation = v),
          ),
          TextField(
            controller: _matchId,
            decoration: const InputDecoration(labelText: 'Match ID', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          if (_compensation) ...[
            TextField(
              controller: _targetEvent,
              decoration: const InputDecoration(
                labelText: 'Compensates event ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
            ),
          ] else ...[
            TextField(
              controller: _teamId,
              decoration: const InputDecoration(labelText: 'Team ID', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _eventType,
              decoration: const InputDecoration(
                labelText: 'Event type (from sport config)',
                hintText: 'goal',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text('Base version (for offline sync): $_baseVersion'),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_compensation ? 'Submit compensation' : 'Submit score event'),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!),
          ],
        ],
      ),
    );
  }
}
