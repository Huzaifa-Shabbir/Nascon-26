import 'api.dart';
import 'db.dart';

class SyncService {
  SyncService(this.api, this.db);

  final ApiClient api;
  final LocalDb db;

  /// Build §5.14 offline-sync body from pending queue and POST it.
  Future<Map<String, dynamic>?> syncPending() async {
    final pending = await db.pendingActions();
    if (pending.isEmpty) return null;

    final deviceId = pending.first['device_id']?.toString() ?? 'device-unknown';
    final actions = pending.map((row) {
      return {
        'action_id': row['action_id'],
        'type': row['type'],
        'payload': row['payload'],
        'base_version': row['base_version'] ?? 0,
        'queued_at': row['queued_at'],
      };
    }).toList();

    final result = await api.offlineSync({
      'device_id': deviceId,
      'actions': actions,
    });

    final results = result['results'];
    if (results is List) {
      for (final r in results) {
        if (r is! Map) continue;
        final actionId = r['action_id']?.toString();
        if (actionId == null) continue;
        final status = r['status']?.toString() ?? 'synced';
        // applied / duplicate / rejected all leave the pending queue
        await db.markDone(actionId, status: status);
      }
    }
    return result;
  }

  static String plainResult(Map<String, dynamic> r) {
    final status = r['status']?.toString() ?? '';
    final resolution = r['resolution']?.toString() ?? '';
    final code = r['error_code']?.toString();
    switch (status) {
      case 'applied':
        if (resolution == 'rebased_append') {
          return 'Applied after catching up with the server.';
        }
        return 'Applied successfully.';
      case 'duplicate':
        return 'Already processed — skipped as duplicate.';
      case 'rejected':
        if (code == 'INVALID_BASE_VERSION') {
          return 'Rejected: your offline base version was ahead of the server.';
        }
        if (code != null && code.isNotEmpty) {
          return 'Rejected: ${friendlyError(ApiException(code, code: code))}';
        }
        return 'Rejected by the server.';
      default:
        return status.isEmpty ? 'Unknown result' : status;
    }
  }
}
