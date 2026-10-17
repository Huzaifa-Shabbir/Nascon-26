import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.code, this.statusCode, this.fields});
  final String message;
  final String? code;
  final int? statusCode;
  final List<String>? fields;

  @override
  String toString() => message;
}

String friendlyError(Object e) {
  if (e is ApiException) {
    if (e.code == 'VALIDATION_ERROR' && e.fields != null && e.fields!.isNotEmpty) {
      return 'Please check: ${e.fields!.join(', ')}';
    }
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
      case 'MIN_POSITION_VIOLATION':
        return 'Moving this player would break position requirements.';
      case 'LEAGUE_NOT_FOUND':
        return 'That league roster scenario was not found. Configure roster first.';
      case 'PLAYER_NOT_FOUND':
        return 'Player not found in this roster.';
      case 'SQUAD_NOT_FOUND':
        return 'Squad not found.';
      case 'MATCH_NOT_FOUND':
        return 'Match not found.';
      case 'MATCH_NOT_IN_PROGRESS':
        return 'Match must be in progress before scoring.';
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
      case 'DUPLICATE_EVENT_ID':
      case 'DUPLICATE_ORDER_ID':
      case 'DUPLICATE_REQUEST_ID':
        return 'This request was already processed with a different body.';
      case 'LEAGUE_EXISTS':
        return 'That league already exists.';
      case 'NOT_FOUND':
        return 'The requested item was not found.';
      default:
        if (e.statusCode != null && e.statusCode! >= 500) {
          return 'Server error. Please try again shortly.';
        }
        return e.message.isNotEmpty ? e.message : 'Something went wrong.';
    }
  }
  final s = e.toString();
  if (s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('Connection refused') ||
      s.contains('TimeoutException')) {
    return 'Cannot reach the server. Check your connection and server URL.';
  }
  return 'Something went wrong. Please try again.';
}

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? 'http://10.0.2.2:8080';

  String baseUrl;
  String? token;

  /// Called on 401 so the app can clear session.
  void Function()? onUnauthorized;

  Uri _u(String path, [Map<String, String>? q]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: q?.isEmpty == true ? null : q);
  }

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
      res = await send().timeout(const Duration(seconds: 12));
    } catch (e) {
      throw ApiException(friendlyError(e));
    }

    Map<String, dynamic> body = {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        } else {
          throw ApiException('Unexpected response format from server.', code: 'MALFORMED_RESPONSE');
        }
      } catch (e) {
        if (e is ApiException) rethrow;
        if (res.statusCode >= 200 && res.statusCode < 300) {
          throw ApiException('Unexpected response format from server.', code: 'MALFORMED_RESPONSE');
        }
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (allowEmpty && body.isEmpty) return {};
      return body;
    }

    if (res.statusCode == 401) {
      onUnauthorized?.call();
    }

    final err = body['error'];
    String code = 'REQUEST_FAILED';
    String message = 'Request failed (${res.statusCode})';
    List<String>? fields;
    if (err is Map) {
      code = (err['code'] ?? code).toString();
      message = (err['message'] ?? message).toString();
      final details = err['details'];
      if (details is Map && details['fields'] is List) {
        fields = (details['fields'] as List).map((e) => e.toString()).toList();
      }
    }
    throw ApiException(message, code: code, statusCode: res.statusCode, fields: fields);
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    return _json(() => http.post(
          _u('/api/v1/auth/login'),
          headers: _headers,
          body: jsonEncode({'email': email, 'password': password}),
        ));
  }

  Future<List<dynamic>> getLeagues() async {
    final body = await _json(() => http.get(_u('/api/v1/leagues'), headers: _headers));
    final list = body['leagues'];
    if (list is! List) {
      throw ApiException('Unexpected leagues response.', code: 'MALFORMED_RESPONSE');
    }
    return list;
  }

  Future<List<dynamic>> getMatches({String? leagueId}) async {
    final q = <String, String>{};
    if (leagueId != null && leagueId.isNotEmpty) q['league_id'] = leagueId;
    final body = await _json(() => http.get(_u('/api/v1/matches', q), headers: _headers));
    final list = body['matches'];
    if (list is! List) {
      throw ApiException('Unexpected matches response.', code: 'MALFORMED_RESPONSE');
    }
    return list;
  }

  Future<Map<String, dynamic>> getClub(String clubId) async {
    return _json(() => http.get(_u('/api/v1/clubs/$clubId'), headers: _headers));
  }

  Future<Map<String, dynamic>> getCatalogue({String? tenantId}) async {
    final q = <String, String>{};
    if (tenantId != null && tenantId.isNotEmpty) q['tenant_id'] = tenantId;
    return _json(() => http.get(_u('/api/v1/catalogue', q), headers: _headers));
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

  Future<Map<String, dynamic>> registerLeague(Map<String, dynamic> body) async {
    return _json(() => http.post(
          _u('/audit/v1/leagues'),
          headers: _headers,
          body: jsonEncode(body),
        ));
  }

  Future<Map<String, dynamic>> rosterSetup(Map<String, dynamic> body) async {
    return _json(() => http.post(
          _u('/audit/v1/roster/setup'),
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
