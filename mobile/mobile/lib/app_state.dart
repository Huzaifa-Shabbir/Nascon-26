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
  String deviceId = '';
  String baseUrl = 'http://10.0.2.2:8080';
  bool ready = false;
  int pendingCount = 0;
  List<Map<String, dynamic>> lastSyncResults = [];
  List<CartItem> cart = [];
  Map<String, dynamic>? lastReceipt;
  StreamSubscription? _connSub;

  static const alphaBlue = 0xFF0B5FFF;
  static const alphaGold = 0xFFFFB800;

  Future<void> _init() async {
    sync = SyncService(api, db);
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
    final jwt = (body['access_token'] ?? body['token'] ?? body['jwt'])?.toString();
    if (jwt == null || jwt.isEmpty) {
      throw ApiException('Login succeeded but no token was returned.');
    }
    token = jwt;
    email = emailIn.trim();
    final user = body['user'];
    final nestedRole = user is Map ? user['role']?.toString() : null;
    role = nestedRole ?? body['role']?.toString() ?? _decodeRole(jwt) ?? _roleFromEmail(email);
    api.token = token;
    await _secure.write(key: 'jwt', value: token!);
    await _secure.write(key: 'email', value: email!);
    await _secure.write(key: 'role', value: role);
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

  Future<void> logout() async {
    token = null;
    email = null;
    role = 'viewer';
    api.token = null;
    cart.clear();
    lastReceipt = null;
    await _secure.delete(key: 'jwt');
    await _secure.delete(key: 'email');
    await _secure.delete(key: 'role');
    notifyListeners();
  }

  Future<void> runSync() async {
    if (netStatus == NetStatus.offline) return;
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
          lastSyncResults = results.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    } catch (_) {
      // stay queued
    }
    pendingCount = await db.pendingCount();
    netStatus = NetStatus.online;
    notifyListeners();
  }

  Future<List<dynamic>> loadMatches({String leagueId = 'league-alpha-1'}) async {
    try {
      final list = await api.getMatches(leagueId: leagueId);
      await db.putCache('matches_$leagueId', list);
      return list;
    } catch (_) {
      final cached = await db.getCache('matches_$leagueId');
      if (cached is List) return cached;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> loadStandings(String leagueId) async {
    try {
      final data = await api.getStandings(leagueId);
      await db.putCache('standings_$leagueId', data);
      return data;
    } catch (_) {
      final cached = await db.getCache('standings_$leagueId');
      if (cached is Map) return Map<String, dynamic>.from(cached);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> loadClub(String clubId) async {
    try {
      final data = await api.getClub(clubId);
      await db.putCache('club_$clubId', data);
      return data;
    } catch (_) {
      final cached = await db.getCache('club_$clubId');
      if (cached is Map) return Map<String, dynamic>.from(cached);
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

  Future<Map<String, dynamic>> submitScoreEvent(Map<String, dynamic> payload, {int baseVersion = 0}) async {
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
    } catch (e) {
      if (e is ApiException && (e.statusCode == null || e.statusCode! >= 500 || e.message.contains('Cannot reach'))) {
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

  Future<Map<String, dynamic>> submitRosterTransfer(Map<String, dynamic> payload, {int baseVersion = 0}) async {
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
    } catch (e) {
      if (e is ApiException && (e.message.contains('Cannot reach') || e.statusCode == null)) {
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
      'discount_code': (discountCode != null && discountCode.isNotEmpty) ? discountCode : null,
      'payment': {'token': paymentToken},
    };
    final result = await api.checkout(body);
    lastReceipt = result;
    clearCart();
    return result;
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }
}
