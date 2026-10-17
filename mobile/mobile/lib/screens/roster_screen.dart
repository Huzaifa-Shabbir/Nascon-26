import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../api.dart';
import '../app_state.dart';

class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  String _action = 'transfer';
  final _playerId = TextEditingController(text: 'p2');
  final _fromSquad = TextEditingController(text: 'sq-a');
  final _toSquad = TextEditingController(text: 'sq-b');
  final _leagueId = TextEditingController(text: AppState.rosterLeagueId);
  final _loanEnd = TextEditingController(text: '2026-12-31');
  final _reason = TextEditingController(text: 'Tactical move');
  bool _busy = false;
  bool _readying = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() {
      _readying = true;
      _message = null;
    });
    try {
      await context.read<AppState>().ensureRosterScenario();
      if (mounted) {
        setState(() {
          _readying = false;
          _message = 'Roster scenario ready (${AppState.rosterLeagueId}).';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _readying = false;
          _message = friendlyError(e);
        });
      }
    }
  }

  Future<void> _submit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm $_action'),
        content: Text(
          '$_action player ${_playerId.text} '
          '${_action == 'release' ? 'from ${_fromSquad.text}' : 'to ${_toSquad.text}'}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    final app = context.read<AppState>();
    final requestId = 'req-${const Uuid().v4().substring(0, 10)}';
    final today = DateTime.now().toUtc().toIso8601String().split('T').first;
    final payload = <String, dynamic>{
      'request_id': requestId,
      'league_id': _leagueId.text.trim(),
      'player_id': _playerId.text.trim(),
      'type': _action,
      'from_squad_id': _fromSquad.text.trim(),
      'to_squad_id': _action == 'release' ? null : _toSquad.text.trim(),
      'effective_date': today,
      'loan_end_date': _action == 'loan' ? _loanEnd.text.trim() : null,
      'reason': _reason.text.trim().isEmpty ? 'Mobile roster change' : _reason.text.trim(),
      'requested_by': app.email ?? 'manager@nascon.test',
    };

    try {
      final result = await app.submitRosterTransfer(payload);
      setState(() {
        if (result['queued'] == true) {
          _message = 'Saved offline. It will sync when you are back online.';
        } else {
          final state = result['state'] ?? 'active';
          _message = 'Accepted ($state).';
        }
      });
    } catch (e) {
      setState(() => _message = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _playerId.dispose();
    _fromSquad.dispose();
    _toSquad.dispose();
    _leagueId.dispose();
    _loanEnd.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roster management'),
        actions: [
          IconButton(
            tooltip: 'Reconfigure scenario',
            onPressed: _readying ? null : _prepare,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _readying
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Uses POST /audit/v1/roster/setup then /transfer. '
                  'Default players: p1 (gk, sq-a), p2 (df, sq-a), p3 (mf, sq-b).',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _action,
                  decoration: const InputDecoration(labelText: 'Action', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                    DropdownMenuItem(value: 'loan', child: Text('Loan')),
                    DropdownMenuItem(value: 'release', child: Text('Release')),
                  ],
                  onChanged: (v) => setState(() => _action = v ?? 'transfer'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _leagueId,
                  decoration: const InputDecoration(labelText: 'League ID', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _playerId,
                  decoration: const InputDecoration(labelText: 'Player ID', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _fromSquad,
                  decoration: const InputDecoration(labelText: 'From squad', border: OutlineInputBorder()),
                ),
                if (_action != 'release') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _toSquad,
                    decoration: const InputDecoration(labelText: 'To squad', border: OutlineInputBorder()),
                  ),
                ],
                if (_action == 'loan') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _loanEnd,
                    decoration: const InputDecoration(
                      labelText: 'Loan end date (YYYY-MM-DD)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
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
                        : Text('Submit $_action'),
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
