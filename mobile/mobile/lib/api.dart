import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.code, this.statusCode});
  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

String friendlyError(Object e) {
  if (e is ApiException) {
    switch (e.code) {
      case 'OUT_OF_STOCK':
        return 'That item just sold out.';
      case 'PAYMENT_DECLINED':
        return 'Payment was declined. Try another token.';
      case 'PAYMENT_CAPTURE_FAILED':
        return 'Payment capture failed. Stock was released.';
      case 'INVALID_DISCOUNT_CODE':
        return 'That discount code is not valid.';
      case 'FORBIDDEN':
        return 'You do not have permission for this action.';
      case 'UNAUTHENTICATED':
        return 'Please sign in again.';
      case 'RATE_LIMITED':
        return 'Too many requests. Wait a moment and try again.';
      case 'SQUAD_FULL':
        return 'The destination squad is full.';
      case 'TRANSFER_WINDOW_CLOSED':
        return 'The transfer window is closed.';
      case 'PLAYER_ON_LOAN':
        return 'This player is currently on loan.';
      case 'NOT_IN_SQUAD':
        return 'Player is not in that squad.';
      case 'CROSS_TENANT_TRANSFER':
        return 'Transfers across tenants are not allowed.';
      case 'TIE_NOT_ALLOWED':
        return 'Match is tied and draws are not allowed.';
      case 'INNINGS_COMPLETE':
        return 'This innings is already complete.';
      case 'SERIES_ALREADY_DECIDED':
        return 'The series is already decided.';
      case 'INVALID_COMPENSATION':
        return 'That compensation target is not valid.';
      case 'EVENT_NOT_FOUND':
        return 'The target event was not found.';
      case 'DUPLICATE_EVENT':
      case 'DUPLICATE_ORDER':
        return 'This request was already processed.';
      default:
        return e.message.isNotEmpty ? e.message : 'Something went wrong.';
    }
  }
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('Connection refused')) {
    return 'Cannot reach the server. Check your connection and server URL.';
  }
  return 'Something went wrong. Please try again.';
}

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? 'http://10.0.2.2:8080';

  String baseUrl;
  String? token;

  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _json(
    Future<http.Response> Function() send, {
    bool allowEmpty = false,
  }) async {
    late http.Response res;
    try {
      res = await send().timeout(const Duration(seconds: 8));
    } catch (e) {
      throw ApiException(friendlyError(e));
    }
    Map<String, dynamic> body = {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (allowEmpty && body.isEmpty) return {};
      return body;
    }
    final err = body['error'];
    String code = 'REQUEST_FAILED';
    String message = 'Request failed (${res.statusCode})';
    if (err is Map) {
      code = (err['code'] ?? code).toString();
      message = (err['message'] ?? message).toString();
    }
    throw ApiException(message, code: code, statusCode: res.statusCode);
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    return _json(() => http.post(
          _u('/api/v1/auth/login'),
          headers: _headers,
          body: jsonEncode({'email': email, 'password': password}),
        ));
  }

  Future<List<dynamic>> getLeagues() async {
    try {
      final body = await _json(() => http.get(_u('/api/v1/leagues'), headers: _headers));
      final list = body['leagues'] ?? body['items'] ?? body;
      if (list is List) return list;
    } catch (_) {}
    return [
      {'league_id': 'league-alpha-1', 'name': 'Alpha League 1', 'tenant_id': 'tenant-alpha'},
      {'league_id': 'league-alpha-2', 'name': 'Alpha League 2', 'tenant_id': 'tenant-alpha'},
      {'league_id': 'league-beta-1', 'name': 'Beta League 1', 'tenant_id': 'tenant-beta'},
    ];
  }

  Future<List<dynamic>> getMatches({String leagueId = 'league-alpha-1'}) async {
    try {
      final body = await _json(() => http.get(
            _u('/api/v1/matches', {'league_id': leagueId}),
            headers: _headers,
          ));
      final list = body['matches'] ?? body['fixtures'] ?? body['items'] ?? body;
      if (list is List) return list;
    } catch (_) {}
    return [
      {
        'match_id': 'RR-L1-R1-M1',
        'league_id': leagueId,
        'home': 'club-alpha-1',
        'away': 'club-alpha-2',
        'status': 'upcoming',
        'round': 1,
      },
      {
        'match_id': 'RR-L1-R1-M2',
        'league_id': leagueId,
        'home': 'club-beta-1',
        'away': 'club-alpha-1',
        'status': 'upcoming',
        'round': 1,
      },
    ];
  }

  Future<Map<String, dynamic>> getClub(String clubId) async {
    try {
      return await _json(() => http.get(_u('/api/v1/clubs/$clubId'), headers: _headers));
    } catch (_) {
      return {
        'club_id': clubId,
        'name': clubId == 'club-alpha-1' ? 'Alpha Club One' : clubId,
        'tenant_id': clubId.startsWith('club-beta') ? 'tenant-beta' : 'tenant-alpha',
        'colors': {'primary': '#0B5FFF', 'accent': '#FFB800'},
      };
    }
  }

  Future<Map<String, dynamic>> getCatalogue() async {
    try {
      return await _json(() => http.get(_u('/api/v1/catalogue'), headers: _headers));
    } catch (_) {
      return {
        'products': [
          {
            'product_id': 'prod-jersey-001',
            'name': 'Alpha Home Jersey',
            'tenant_id': 'tenant-alpha',
            'variants': [
              {
                'variant_id': 'var-jersey-001-M',
                'size': 'M',
                'price_minor': 450000,
                'currency': 'PKR',
              },
              {
                'variant_id': 'var-jersey-001-L',
                'size': 'L',
                'price_minor': 450000,
                'currency': 'PKR',
              },
            ],
          },
        ],
      };
    }
  }

  Future<Map<String, dynamic>> getStandings(String leagueId) async {
    return _json(() => http.get(_u('/audit/v1/standings/$leagueId'), headers: _headers));
  }

  Future<Map<String, dynamic>> getScore(String matchId) async {
    return _json(() => http.get(_u('/audit/v1/score/$matchId'), headers: _headers));
  }

  Future<Map<String, dynamic>> postEvent(Map<String, dynamic> body) async {
    return _json(() => http.post(
          _u('/audit/v1/events'),
          headers: _headers,
          body: jsonEncode(body),
        ));
  }

  Future<Map<String, dynamic>> rosterTransfer(Map<String, dynamic> body) async {
    return _json(() => http.post(
          _u('/audit/v1/roster/transfer'),
          headers: _headers,
          body: jsonEncode(body),
        ));
  }

  Future<Map<String, dynamic>> getInventory(String variantId) async {
    return _json(() => http.get(_u('/audit/v1/inventory/$variantId'), headers: _headers));
  }

  Future<Map<String, dynamic>> checkout(Map<String, dynamic> body) async {
    return _json(() => http.post(
          _u('/audit/v1/checkout'),
          headers: _headers,
          body: jsonEncode(body),
        ));
  }

  Future<Map<String, dynamic>> offlineSync(Map<String, dynamic> body) async {
    return _json(() => http.post(
          _u('/audit/v1/offline-sync'),
          headers: _headers,
          body: jsonEncode(body),
        ));
  }

  Future<bool> ping() async {
    try {
      final res = await http
          .get(_u('/health'), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
