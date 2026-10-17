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
  final _matchId = TextEditingController(text: 'RR-L1-R1-M1');
  final _teamId = TextEditingController(text: 'club-alpha-1');
  final _eventType = TextEditingController(text: 'goal');
  final _value = TextEditingController(text: '1');
  final _targetEvent = TextEditingController();
  bool _compensation = false;
  bool _busy = false;
  String? _message;
  int _baseVersion = 0;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final eventId = 'evt-${const Uuid().v4().substring(0, 12)}';
    final Map<String, dynamic> payload;
    if (_compensation) {
      payload = {
        'event_id': eventId,
        'match_id': _matchId.text.trim(),
        'type': 'compensation',
        'payload': {
          'target_event_id': _targetEvent.text.trim(),
        },
        'ts': '${DateTime.now().toUtc().toIso8601String().split('.').first}Z',
      };
    } else {
      payload = {
        'event_id': eventId,
        'match_id': _matchId.text.trim(),
        'type': 'score',
        'payload': {
          'team_id': _teamId.text.trim(),
          'event_type': _eventType.text.trim(),
          'value': int.tryParse(_value.text.trim()) ?? 1,
        },
        'ts': '${DateTime.now().toUtc().toIso8601String().split('.').first}Z',
      };
    }

    try {
      final result = await context.read<AppState>().submitScoreEvent(
            payload,
            baseVersion: _baseVersion,
          );
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
      setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scoring entry')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          if (_compensation)
            TextField(
              controller: _targetEvent,
              decoration: const InputDecoration(
                labelText: 'Target event ID',
                border: OutlineInputBorder(),
              ),
            )
          else ...[
            TextField(
              controller: _teamId,
              decoration: const InputDecoration(labelText: 'Team ID', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _eventType,
              decoration: const InputDecoration(
                labelText: 'Event type (from sport config)',
                hintText: 'goal / point / run …',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _value,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Value', border: OutlineInputBorder()),
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
