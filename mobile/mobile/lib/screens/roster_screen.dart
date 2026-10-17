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
  final _playerId = TextEditingController(text: 'player-alpha-2');
  final _fromSquad = TextEditingController(text: 'club-alpha-2');
  final _toSquad = TextEditingController(text: 'club-alpha-1');
  final _leagueId = TextEditingController(text: 'league-alpha-1');
  final _loanEnd = TextEditingController(text: '2026-12-31');
  bool _busy = false;
  String? _message;

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
    final requestId = 'req-${const Uuid().v4().substring(0, 10)}';
    final payload = <String, dynamic>{
      'request_id': requestId,
      'league_id': _leagueId.text.trim(),
      'player_id': _playerId.text.trim(),
      'action': _action,
      'from_squad_id': _fromSquad.text.trim(),
      if (_action != 'release') 'to_squad_id': _toSquad.text.trim(),
      if (_action == 'loan') 'loan_end_date': _loanEnd.text.trim(),
      'who': 'manager@nascon.test',
      'effective_date': DateTime.now().toUtc().toIso8601String().split('T').first,
    };

    try {
      final result = await context.read<AppState>().submitRosterTransfer(payload);
      setState(() {
        if (result['queued'] == true) {
          _message = 'Saved offline. It will sync when you are back online.';
        } else {
          _message = 'Transfer recorded successfully.';
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
      appBar: AppBar(title: const Text('Roster management')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _action,
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
              decoration: const InputDecoration(labelText: 'Loan end date (YYYY-MM-DD)', border: OutlineInputBorder()),
            ),
          ],
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
