import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'db.dart';
import 'sync.dart';

enum NetStatus { online, offline, syncing }

class CartItem {
  CartItem({required this.variantId, required this.name, required this.priceMinor, this.qty = 1});
  final String variantId;
  final String name;
  final int priceMinor;
  int qty;
}

class AppState extends ChangeNotifier {
  AppState() {
    _init();
  }

  final api = ApiClient();
  final db = LocalDb();
  late final SyncService sync;
  final _secure = const FlutterSecureStorage();
  final _uuid = const Uuid();

  NetStatus netStatus = NetStatus.offline;
  String? token;
  String? email;
  String role = 'viewer';
  String? tenantId;
  String? clubId;
  String? leagueId;
  String? playerId;
  String deviceId = '';
  String baseUrl = 'http://10.0.2.2:8080';
  bool ready = false;
  int pendingCount = 0;
  List<Map<String, dynamic>> lastSyncResults = [];
  List<CartItem> cart = [];
  Map<String, dynamic>? lastReceipt;
  bool _checkoutInFlight = false;
  StreamSubscription? _connSub;
  bool _loggingOut = false;

  /// Demo competition league used by fixtures/standings screens.
  static const demoLeagueId = 'lg-mobile-1';
  static const rosterLeagueId = 'lg-r1';

  static const alphaBlue = 0xFF0B5FFF;
  static const alphaGold = 0xFFFFB800;

  Future<void> _init() async {
    sync = SyncService(api, db);
    api.onUnauthorized = () {
      if (!_loggingOut) {
        logout(reason: 'session_expired');
      }
    };
    baseUrl = await db.getKv('base_url') ?? 'http://10.0.2.2:8080';
    api.baseUrl = baseUrl;
    deviceId = await db.getKv('device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = 'device-${_uuid.v4().substring(0, 8)}';
      await db.setKv('device_id', deviceId);
    }
    token = await _secure.read(key: 'jwt');
    email = await _secure.read(key: 'email');
    role = await _secure.read(key: 'role') ?? _roleFromEmail(email);
    tenantId = await _secure.read(key: 'tenant_id');
    clubId = await _secure.read(key: 'club_id');
    leagueId = await _secure.read(key: 'league_id');
    playerId = await _secure.read(key: 'player_id');
    api.token = token;
    pendingCount = await db.pendingCount();
    _connSub = Connectivity().onConnectivityChanged.listen((_) => refreshConnectivity());
    await refreshConnectivity();
    ready = true;
    notifyListeners();
  }

  String _roleFromEmail(String? e) {
    switch (e) {
      case 'admin@nascon.test':
        return 'super_admin';
      case 'organizer@nascon.test':
        return 'league_organizer';
      case 'manager@nascon.test':
        return 'club_manager';
      case 'player@nascon.test':
        return 'player';
      default:
        return 'viewer';
    }
  }

  String roleLabel() {
    switch (role) {
      case 'super_admin':
        return 'Super Admin';
      case 'league_organizer':
        return 'League Organizer';
      case 'club_manager':
        return 'Club Manager';
      case 'player':
        return 'Player';
      default:
        return 'Viewer';
    }
  }

  bool get canScore => role == 'super_admin' || role == 'league_organizer';
  bool get canManageRoster => role == 'super_admin' || role == 'club_manager';

  String get effectiveClubId => clubId ?? 'club-alpha-1';

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    api.baseUrl = baseUrl;
    await db.setKv('base_url', baseUrl);
    await refreshConnectivity();
    notifyListeners();
  }

  Future<void> refreshConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    final hasNet = results.any((r) => r != ConnectivityResult.none);
    if (!hasNet) {
      netStatus = NetStatus.offline;
      notifyListeners();
      return;
    }
    final ok = await api.ping();
    if (!ok) {
      netStatus = NetStatus.offline;
      notifyListeners();
      return;
    }
    if (pendingCount > 0 && token != null) {
      await runSync();
    } else {
      netStatus = NetStatus.online;
      notifyListeners();
    }
  }

  Future<void> login(String emailIn, String password) async {
    final body = await api.login(emailIn.trim(), password);
    final jwt = body['access_token']?.toString();
    if (jwt == null || jwt.isEmpty) {
      throw ApiException('Login succeeded but no token was returned.');
    }
    final user = body['user'];
    if (user is! Map) {
      throw ApiException('Login response missing user profile.', code: 'MALFORMED_RESPONSE');
    }

    // Clear previous user's cached data before adopting new session.
    await db.clearCache();
    cart.clear();
    lastReceipt = null;
    lastSyncResults = [];

    token = jwt;
    email = emailIn.trim();
    role = user['role']?.toString() ?? _decodeRole(jwt) ?? _roleFromEmail(email);
    tenantId = user['tenant_id']?.toString();
    clubId = user['club_id']?.toString();
    leagueId = user['league_id']?.toString();
    playerId = user['player_id']?.toString();
    api.token = token;

    await _secure.write(key: 'jwt', value: token!);
    await _secure.write(key: 'email', value: email!);
    await _secure.write(key: 'role', value: role);
    await _secure.write(key: 'tenant_id', value: tenantId ?? '');
    await _secure.write(key: 'club_id', value: clubId ?? '');
    await _secure.write(key: 'league_id', value: leagueId ?? '');
    await _secure.write(key: 'player_id', value: playerId ?? '');

    netStatus = NetStatus.online;
    notifyListeners();
    await runSync();
  }

  String? _decodeRole(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      var payload = parts[1];
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final map = jsonDecode(utf8.decode(base64Url.decode(payload)));
      if (map is Map && map['role'] != null) return map['role'].toString();
    } catch (_) {}
    return null;
  }

  Future<void> logout({String reason = 'user'}) async {
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      token = null;
      email = null;
      role = 'viewer';
      tenantId = null;
      clubId = null;
      leagueId = null;
      playerId = null;
      api.token = null;
      cart.clear();
      lastReceipt = null;
      lastSyncResults = [];
      await db.clearCache();
      await _secure.delete(key: 'jwt');
      await _secure.delete(key: 'email');
      await _secure.delete(key: 'role');
      await _secure.delete(key: 'tenant_id');
      await _secure.delete(key: 'club_id');
      await _secure.delete(key: 'league_id');
      await _secure.delete(key: 'player_id');
      notifyListeners();
    } finally {
      _loggingOut = false;
    }
  }

  Future<void> runSync() async {
    if (netStatus == NetStatus.offline && !(await api.ping())) return;
    final pending = await db.pendingCount();
    if (pending == 0) {
      pendingCount = 0;
      netStatus = NetStatus.online;
      notifyListeners();
      return;
    }
    netStatus = NetStatus.syncing;
    notifyListeners();
    try {
      final result = await sync.syncPending();
      if (result != null) {
        final results = result['results'];
        if (results is List) {
          lastSyncResults =
              results.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
      netStatus = NetStatus.online;
    } catch (e) {
      // Keep items queued; surface offline if unreachable.
      if (e is ApiException &&
          (e.message.contains('Cannot reach') || e.statusCode == null)) {
        netStatus = NetStatus.offline;
      } else {
        netStatus = NetStatus.online;
      }
    }
    pendingCount = await db.pendingCount();
    notifyListeners();
  }

  /// Ensures a playable demo league exists (POST /audit/v1/leagues once).
  Future<void> ensureDemoLeague() async {
    final matches = await api.getMatches(leagueId: demoLeagueId);
    if (matches.isNotEmpty) return;
    try {
      await api.registerLeague({
        'league_id': demoLeagueId,
        'sport_id': 'football',
        'teams': ['t1', 't2', 't3', 't4'],
        'fixtures': [
          {'match_id': 'm-demo-1', 'home': 't1', 'away': 't2'},
          {'match_id': 'm-demo-2', 'home': 't3', 'away': 't4'},
          {'match_id': 'm-demo-3', 'home': 't1', 'away': 't3'},
          {'match_id': 'm-demo-4', 'home': 't2', 'away': 't4'},
        ],
        'qualification': {'spots': 2},
        'lots_seed': 42,
      });
    } on ApiException catch (e) {
      if (e.code != 'LEAGUE_EXISTS') rethrow;
    }
  }

  Future<void> ensureRosterScenario() async {
    await api.rosterSetup({
      'league': {
        'league_id': rosterLeagueId,
        'tenant_id': 'tenant-alpha',
        'sport_id': 'football',
        'transfer_window': {'open': '2026-01-01', 'close': '2026-12-31'},
        'max_squad_size': 25,
        'required_positions': {'gk': 1},
      },
      'squads': [
        {
          'squad_id': 'sq-a',
          'club_id': 'club-alpha-1',
          'tenant_id': 'tenant-alpha',
          'name': 'Alpha United',
        },
        {
          'squad_id': 'sq-b',
          'club_id': 'club-alpha-2',
          'tenant_id': 'tenant-alpha',
          'name': 'Alpha Rovers',
        },
      ],
      'players': [
        {
          'player_id': 'p1',
          'name': 'Ali Hassan',
          'position': 'gk',
          'squad_id': 'sq-a',
          'role': 'captain',
        },
        {
          'player_id': 'p2',
          'name': 'Hamza Iqbal',
          'position': 'df',
          'squad_id': 'sq-a',
          'role': 'starter',
        },
        {
          'player_id': 'p3',
          'name': 'Spare Mid',
          'position': 'mf',
          'squad_id': 'sq-b',
          'role': 'starter',
        },
      ],
      'matches_in_progress': [],
    });
  }

  Future<List<dynamic>> loadMatches({String leagueId = demoLeagueId}) async {
    try {
      await ensureDemoLeague();
      final list = await api.getMatches(leagueId: leagueId);
      await db.putCache('matches_$leagueId', list);
      return list;
    } catch (e) {
      if (netStatus == NetStatus.offline || e.toString().contains('Cannot reach')) {
        final cached = await db.getCache('matches_$leagueId');
        if (cached is List) return cached;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> loadStandings(String leagueId) async {
    try {
      await ensureDemoLeague();
      final data = await api.getStandings(leagueId);
      await db.putCache('standings_$leagueId', data);
      return data;
    } catch (e) {
      if (netStatus == NetStatus.offline || e.toString().contains('Cannot reach')) {
        final cached = await db.getCache('standings_$leagueId');
        if (cached is Map) return Map<String, dynamic>.from(cached);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> loadClub(String clubId) async {
    try {
      final data = await api.getClub(clubId);
      await db.putCache('club_$clubId', data);
      return data;
    } catch (e) {
      if (netStatus == NetStatus.offline || e.toString().contains('Cannot reach')) {
        final cached = await db.getCache('club_$clubId');
        if (cached is Map) return Map<String, dynamic>.from(cached);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> loadScore(String matchId) async {
    return api.getScore(matchId);
  }

  String _nowIso() {
    final n = DateTime.now().toUtc();
    return '${n.toIso8601String().split('.').first}Z';
  }

  Future<Map<String, dynamic>> submitScoreEvent(
    Map<String, dynamic> payload, {
    int baseVersion = 0,
  }) async {
    if (netStatus == NetStatus.offline) {
      final actionId = 'act-${_uuid.v4().substring(0, 12)}';
      await db.enqueueAction(
        deviceId: deviceId,
        actionId: actionId,
        type: 'score_event',
        payload: payload,
        baseVersion: baseVersion,
        queuedAt: _nowIso(),
      );
      pendingCount = await db.pendingCount();
      notifyListeners();
      return {'queued': true, 'action_id': actionId};
    }
    try {
      return await api.postEvent(payload);
    } on ApiException catch (e) {
      if (e.statusCode == null || e.message.contains('Cannot reach')) {
        final actionId = 'act-${_uuid.v4().substring(0, 12)}';
        await db.enqueueAction(
          deviceId: deviceId,
          actionId: actionId,
          type: 'score_event',
          payload: payload,
          baseVersion: baseVersion,
          queuedAt: _nowIso(),
        );
        pendingCount = await db.pendingCount();
        netStatus = NetStatus.offline;
        notifyListeners();
        return {'queued': true, 'action_id': actionId};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> submitRosterTransfer(
    Map<String, dynamic> payload, {
    int baseVersion = 0,
  }) async {
    if (netStatus == NetStatus.offline) {
      final actionId = 'act-${_uuid.v4().substring(0, 12)}';
      await db.enqueueAction(
        deviceId: deviceId,
        actionId: actionId,
        type: 'roster_transfer',
        payload: payload,
        baseVersion: baseVersion,
        queuedAt: _nowIso(),
      );
      pendingCount = await db.pendingCount();
      notifyListeners();
      return {'queued': true, 'action_id': actionId};
    }
    try {
      return await api.rosterTransfer(payload);
    } on ApiException catch (e) {
      if (e.statusCode == null || e.message.contains('Cannot reach')) {
        final actionId = 'act-${_uuid.v4().substring(0, 12)}';
        await db.enqueueAction(
          deviceId: deviceId,
          actionId: actionId,
          type: 'roster_transfer',
          payload: payload,
          baseVersion: baseVersion,
          queuedAt: _nowIso(),
        );
        pendingCount = await db.pendingCount();
        netStatus = NetStatus.offline;
        notifyListeners();
        return {'queued': true, 'action_id': actionId};
      }
      rethrow;
    }
  }

  void addToCart(CartItem item) {
    final existing = cart.where((c) => c.variantId == item.variantId).toList();
    if (existing.isNotEmpty) {
      existing.first.qty += item.qty;
    } else {
      cart.add(item);
    }
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    notifyListeners();
  }

  int get cartTotalMinor => cart.fold(0, (s, c) => s + c.priceMinor * c.qty);

  Future<Map<String, dynamic>> checkout({
    required String paymentToken,
    String? discountCode,
  }) async {
    if (_checkoutInFlight) {
      throw ApiException('Checkout already in progress.', code: 'IN_FLIGHT');
    }
    if (cart.isEmpty) {
      throw ApiException('Your cart is empty.', code: 'VALIDATION_ERROR');
    }
    _checkoutInFlight = true;
    notifyListeners();
    try {
      final orderId = 'ord-${_uuid.v4().substring(0, 12)}';
      final items = cart
          .map((c) => {
                'variant_id': c.variantId,
                'quantity': c.qty,
              })
          .toList();
      final body = <String, dynamic>{
        'order_id': orderId,
        'customer_id': email ?? 'cust-mobile',
        'items': items,
        'discount_code':
            (discountCode != null && discountCode.isNotEmpty) ? discountCode : null,
        'payment': {'token': paymentToken},
      };
      final result = await api.checkout(body);
      lastReceipt = result;
      clearCart();
      return result;
    } finally {
      _checkoutInFlight = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}
