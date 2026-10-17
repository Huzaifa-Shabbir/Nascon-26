import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const brandInk = Color(0xff304916);
const brandGreen = Color(0xff92d33d);
const brandCream = Color(0xfff3f5ed);
const brandGradient = LinearGradient(
  colors: [Color(0xff3e571d), Color(0xff98d844)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);
final app = AppState();

const demoRoles = {
  'super_admin': 'Platform Admin',
  'league_organizer': 'League Organizer',
  'club_manager': 'Club Manager',
  'player': 'Player',
  'viewer': 'Viewer',
};
const demoEmails = {
  'super_admin': 'admin@nascon.test',
  'league_organizer': 'organizer@nascon.test',
  'club_manager': 'manager@nascon.test',
  'player': 'player@nascon.test',
  'viewer': 'viewer@nascon.test',
};

class MatchData {
  MatchData(
    this.id,
    this.home,
    this.away,
    this.sport,
    this.status,
    this.homeScore,
    this.awayScore,
    this.venue,
    this.time, {
    this.scoringOptions = const {'Goal': 1},
    this.day = 'Today',
  });
  final String id, home, away, sport, venue, time, day;
  String status;
  int homeScore, awayScore;
  final Map<String, int> scoringOptions;
  final List<ScoreEntry> events = [];
}

class ScoreEntry {
  ScoreEntry(
    this.id,
    this.team,
    this.label,
    this.points, {
    this.compensated = false,
    this.reason = '',
  });
  final String id, team, label;
  final int points;
  bool compensated;
  String reason;
}

class PlayerData {
  PlayerData(
    this.id,
    this.name,
    this.position,
    this.role,
    this.squad, {
    this.onLoan = false,
  });
  final String id, name, position;
  String role, squad;
  bool onLoan;
}

class ProductData {
  ProductData(
    this.id,
    this.name,
    this.category,
    this.asset,
    this.price,
    this.stock,
  );
  final String id, name, category, asset;
  final int price;
  int stock;
}

class OrderData {
  OrderData(
    this.id,
    this.total,
    this.subtotal,
    this.discount,
    this.items,
    this.createdAt,
  );
  final String id;
  final int total, subtotal, discount;
  final Map<String, int> items;
  final DateTime createdAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'total': total,
    'subtotal': subtotal,
    'discount': discount,
    'items': items,
    'createdAt': createdAt.toIso8601String(),
  };
}

class PendingAction {
  PendingAction(
    this.id,
    this.type,
    this.description,
    this.payload,
    this.queuedAt,
    this.baseVersion, {
    this.status = 'pending',
    this.result = 'Waiting for connection',
  });
  final String id, type, description, queuedAt;
  final Map<String, dynamic> payload;
  final int baseVersion;
  String status, result;
  Map<String, dynamic> toJson() => {
    'action_id': id,
    'type': type,
    'queued_at': queuedAt,
    'base_version': baseVersion,
    'payload': payload,
    'description': description,
    'status': status,
    'result': result,
  };
}

class AppState extends ChangeNotifier {
  late SharedPreferences prefs;
  final secure = const FlutterSecureStorage();
  String role = 'viewer', email = '', serverUrl = 'http://10.0.2.2:8080';
  bool loggedIn = false, online = true, syncing = false;
  int revision = 0;
  final cart = <String, int>{};
  final orders = <OrderData>[];
  final pending = <PendingAction>[];
  final rosterHistory = <String>[];
  final matches = <MatchData>[
    MatchData(
      'm1',
      'Alpha Falcons',
      'Crescent United',
      'Football',
      'Live',
      2,
      1,
      'FAST Main Ground',
      '12:30 PM',
    ),
    MatchData(
      'm2',
      'North Stars',
      'Alpha Falcons',
      'Basketball',
      'Upcoming',
      0,
      0,
      'Indoor Court',
      '02:00 PM',
      scoringOptions: {'Free throw': 1, 'Two pointer': 2, 'Three pointer': 3},
    ),
    MatchData(
      'm3',
      'Alpha Falcons',
      'Capital Kings',
      'Cricket',
      'Upcoming',
      0,
      0,
      'Cricket Oval',
      '03:30 PM',
      scoringOptions: {
        'Dot ball': 0,
        'Single': 1,
        'Two': 2,
        'Four': 4,
        'Six': 6,
        'Wide': 1,
        'No ball': 1,
        'Wicket': 0,
      },
    ),
    MatchData(
      'm4',
      'Pixel Raiders',
      'North Stars',
      'Esports',
      'Completed',
      2,
      1,
      'Gaming Arena',
      '10:00 AM',
      scoringOptions: {'Round win': 1},
    ),
    MatchData(
      'm5',
      'Crescent United',
      'North Stars',
      'Football',
      'Upcoming',
      0,
      0,
      'FAST Main Ground',
      '10:00 AM',
      day: 'Tomorrow',
    ),
    MatchData(
      'm6',
      'Capital Kings',
      'Alpha Falcons',
      'Football',
      'Completed',
      0,
      3,
      'City Sports Complex',
      'Yesterday',
    ),
  ];
  final players = <PlayerData>[
    PlayerData(
      'player-alpha-1',
      'Ali Hassan',
      'Forward',
      'captain',
      'Alpha Falcons',
    ),
    PlayerData('p2', 'Hamza Khan', 'Goalkeeper', 'starter', 'Alpha Falcons'),
    PlayerData(
      'p3',
      'Bilal Ahmed',
      'Midfielder',
      'vice_captain',
      'Alpha Falcons',
    ),
    PlayerData('p4', 'Saad Malik', 'Defender', 'starter', 'Alpha Falcons'),
    PlayerData('p5', 'Omar Farooq', 'Forward', 'substitute', 'Alpha Falcons'),
    PlayerData('p6', 'Zain Ali', 'Goalkeeper', 'substitute', 'Alpha Falcons'),
  ];
  final products = <ProductData>[
    ProductData(
      'prod-jersey-001',
      'Falcons Home Jersey',
      'Apparel',
      '',
      450000,
      6,
    ),
    ProductData('training-top', 'Training Tee', 'Apparel', '', 280000, 12),
    ProductData('match-ball', 'Matchday Football', 'Equipment', '', 320000, 8),
    ProductData('club-cap', 'Club Cap', 'Accessories', '', 150000, 10),
    ProductData('kit-bag', 'Training Backpack', 'Accessories', '', 380000, 5),
    ProductData(
      'season-pass',
      'Digital Season Pass',
      'Digital',
      '',
      120000,
      30,
    ),
  ];
  bool get canScore => role == 'league_organizer' || role == 'super_admin';
  bool get canManage => role == 'club_manager' || role == 'super_admin';
  int get cartCount => cart.values.fold(0, (a, b) => a + b);
  int get cartSubtotal =>
      cart.entries.fold(0, (a, e) => a + productForKey(e.key).price * e.value);
  int get pendingCount => pending.where((a) => a.status == 'pending').length;
  String get displayName => switch (role) {
    'super_admin' => 'Ayesha',
    'league_organizer' => 'Hassan',
    'club_manager' => 'Zara',
    'player' => 'Ali',
    _ => 'Sports fan',
  };

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 10),
    );
    serverUrl = prefs.getString('serverUrl') ?? serverUrl;
    online = prefs.getBool('online') ?? true;
    try {
      final savedRole = await secure
          .read(key: 'demoRole')
          .timeout(const Duration(seconds: 3));
      if (savedRole != null && demoRoles.containsKey(savedRole)) {
        role = savedRole;
        email = demoEmails[role]!;
        loggedIn = true;
      }
    } catch (_) {}
    try {
      final raw = prefs.getString('demoState');
      if (raw != null) {
        final s = jsonDecode(raw) as Map<String, dynamic>;
        cart.addAll(Map<String, int>.from(s['cart'] ?? {}));
        rosterHistory.addAll(List<String>.from(s['history'] ?? []));
        for (final p in (s['players'] ?? []) as List) {
          final index = players.indexWhere((v) => v.id == p['id']);
          final player = PlayerData(
            p['id'],
            p['name'],
            p['position'],
            p['role'],
            p['squad'],
            onLoan: p['onLoan'] ?? false,
          );
          if (index < 0) {
            players.add(player);
          } else {
            players[index] = player;
          }
        }
        for (final m in (s['matches'] ?? []) as List) {
          final match = matches.where((x) => x.id == m['id']).firstOrNull;
          if (match == null) continue;
          match.status = m['status'];
          match.homeScore = m['home'];
          match.awayScore = m['away'];
          for (final e in m['events']) {
            match.events.add(
              ScoreEntry(
                e['id'],
                e['team'],
                e['label'],
                e['points'],
                compensated: e['compensated'],
                reason: e['reason'] ?? '',
              ),
            );
          }
        }
        for (final p in (s['pending'] ?? []) as List) {
          pending.add(
            PendingAction(
              p['action_id'],
              p['type'],
              p['description'],
              Map<String, dynamic>.from(p['payload']),
              p['queued_at'],
              p['base_version'],
              status: p['status'],
              result: p['result'],
            ),
          );
        }
        for (final o in (s['orders'] ?? []) as List) {
          orders.add(
            OrderData(
              o['id'],
              o['total'],
              o['subtotal'],
              o['discount'],
              Map<String, int>.from(o['items']),
              DateTime.parse(o['createdAt']),
            ),
          );
        }
        for (final p in products) {
          p.stock = (s['stock'] ?? {})[p.id] ?? p.stock;
        }
      }
    } catch (_) {
      /* Invalid local demo cache is replaced on next successful save. */
    }
    if (matches.first.events.isEmpty) {
      matches.first.events.addAll([
        ScoreEntry('demo-e1', 'Alpha Falcons', 'Goal · 18 min', 1),
        ScoreEntry('demo-e2', 'Crescent United', 'Goal · 32 min', 1),
        ScoreEntry('demo-e3', 'Alpha Falcons', 'Goal · 54 min', 1),
      ]);
    }
  }

  Future<void> save() async {
    await prefs.setString(
      'demoState',
      jsonEncode({
        'cart': cart,
        'history': rosterHistory,
        'players': players
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'position': p.position,
                'role': p.role,
                'squad': p.squad,
                'onLoan': p.onLoan,
              },
            )
            .toList(),
        'matches': matches
            .map(
              (m) => {
                'id': m.id,
                'status': m.status,
                'home': m.homeScore,
                'away': m.awayScore,
                'events': m.events
                    .map(
                      (e) => {
                        'id': e.id,
                        'team': e.team,
                        'label': e.label,
                        'points': e.points,
                        'compensated': e.compensated,
                        'reason': e.reason,
                      },
                    )
                    .toList(),
              },
            )
            .toList(),
        'pending': pending.map((a) => a.toJson()).toList(),
        'orders': orders.map((o) => o.toJson()).toList(),
        'stock': {for (final p in products) p.id: p.stock},
      }),
    );
  }

  Future<bool> login(
    String input,
    String password, {
    bool remember = true,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final entry = demoEmails.entries
        .where((e) => e.value == input.trim().toLowerCase())
        .firstOrNull;
    if (entry == null || password != 'Nascon@26') return false;
    role = entry.key;
    email = entry.value;
    loggedIn = true;
    if (remember) {
      try {
        await secure
            .write(key: 'demoRole', value: role)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    } else {
      try {
        await secure
            .delete(key: 'demoRole')
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    loggedIn = false;
    try {
      await secure.delete(key: 'demoRole').timeout(const Duration(seconds: 3));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setOnline(bool value) async {
    online = value;
    await prefs.setBool('online', value);
    notifyListeners();
  }

  Future<void> setServer(String value) async {
    serverUrl = value;
    await prefs.setString('serverUrl', value);
    notifyListeners();
  }

  ProductData productForKey(String key) =>
      products.firstWhere((p) => p.id == key.split('|').first);
  void addCart(ProductData p, String size) {
    final key = '${p.id}|$size';
    final count = cart.entries
        .where((e) => e.key.startsWith('${p.id}|'))
        .fold(0, (n, e) => n + e.value);
    if (count >= p.stock) {
      throw Exception('No more stock available for this item.');
    }
    cart[key] = (cart[key] ?? 0) + 1;
    save();
    notifyListeners();
  }

  void setCartQuantity(String key, int quantity) {
    if (quantity <= 0) {
      cart.remove(key);
    } else {
      final p = productForKey(key);
      if (quantity > p.stock) throw Exception('Only ${p.stock} left in stock.');
      cart[key] = quantity;
    }
    save();
    notifyListeners();
  }

  Future<OrderData> checkout(String token, String discountCode) async {
    if (!online) {
      throw Exception('Reconnect to place your order. Your cart is saved.');
    }
    if (cart.isEmpty) throw Exception('Add an item to your cart first.');
    if (discountCode.isNotEmpty && discountCode != 'WELCOME10') {
      throw Exception('That code is not valid. Try WELCOME10.');
    }
    for (final p in products) {
      final quantity = cart.entries
          .where((e) => e.key.startsWith('${p.id}|'))
          .fold(0, (n, e) => n + e.value);
      if (quantity > p.stock) {
        throw Exception('${p.name} no longer has enough stock.');
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (token == 'tok_declined') {
      throw Exception(
        'Payment declined. Your cart and stock are unchanged. Try another payment option.',
      );
    }
    if (token == 'tok_capture_fail') {
      throw Exception(
        'Payment could not be completed. No charge was made. Please retry.',
      );
    }
    final subtotal = cartSubtotal,
        discount = discountCode == 'WELCOME10'
            ? (cartSubtotal * 0.1).floor()
            : 0;
    final order = OrderData(
      'NS-${DateTime.now().millisecondsSinceEpoch}',
      subtotal - discount,
      subtotal,
      discount,
      Map.from(cart),
      DateTime.now(),
    );
    for (final e in cart.entries) {
      productForKey(e.key).stock -= e.value;
    }
    orders.insert(0, order);
    cart.clear();
    await save();
    notifyListeners();
    return order;
  }

  void queueAction(
    String type,
    Map<String, dynamic> payload,
    String description,
  ) {
    final id = 'a-${DateTime.now().microsecondsSinceEpoch}';
    final match = matches.where((m) => m.id == payload['match_id']).firstOrNull;
    pending.add(
      PendingAction(
        id,
        type,
        description,
        payload,
        DateTime.now().toUtc().toIso8601String(),
        match?.events.length ?? rosterHistory.length,
      ),
    );
    save();
    notifyListeners();
  }

  void addScore(MatchData m, String team, String label, int points) {
    if (!canScore) {
      throw Exception('Only the league organizer can enter scores.');
    }
    if (m.status == 'Completed') {
      throw Exception('This match has ended. You can still correct an event.');
    }
    final id = 'evt-${DateTime.now().microsecondsSinceEpoch}';
    if (!online) {
      queueAction('score_event', {
        'event_id': id,
        'match_id': m.id,
        'type': 'score',
        'payload': {
          'team_id': team,
          'event_type': label.toLowerCase().replaceAll(' ', '_'),
        },
      }, '$label for $team');
      return;
    }
    m.status = 'Live';
    m.events.add(ScoreEntry(id, team, label, points));
    if (team == m.home) {
      m.homeScore += points;
    } else {
      m.awayScore += points;
    }
    revision++;
    save();
    notifyListeners();
  }

  void compensate(MatchData m, ScoreEntry entry, {String reason = ''}) {
    if (!canScore || entry.compensated) return;
    if (!online) {
      queueAction('score_event', {
        'event_id': 'evt-${DateTime.now().microsecondsSinceEpoch}',
        'match_id': m.id,
        'type': 'compensation',
        'payload': {'compensates': entry.id, 'reason': reason},
      }, 'Correct ${entry.label}');
      return;
    }
    entry.compensated = true;
    entry.reason = reason;
    if (entry.team == m.home) {
      m.homeScore -= entry.points;
    } else {
      m.awayScore -= entry.points;
    }
    revision++;
    save();
    notifyListeners();
  }

  void finishMatch(MatchData m) {
    if (!canScore) return;
    if (!online) throw Exception('Reconnect before ending a match.');
    m.status = 'Completed';
    revision++;
    save();
    notifyListeners();
  }

  Future<void> rosterAction(
    PlayerData p,
    String type,
    String destination,
    String reason, {
    String? loanEnd,
  }) async {
    if (!canManage) {
      throw Exception('Only a club manager can change the roster.');
    }
    if (p.onLoan) {
      throw Exception(
        'This player is on loan and must return before another move.',
      );
    }
    if (p.position == 'Goalkeeper' &&
        players
                .where((v) => v.squad == p.squad && v.position == 'Goalkeeper')
                .length <=
            1) {
      throw Exception('Keep at least one goalkeeper in the squad.');
    }
    if (!online) {
      queueAction('roster_transfer', {
        'request_id': 'tr-${DateTime.now().microsecondsSinceEpoch}',
        'league_id': 'league-alpha-1',
        'player_id': p.id,
        'type': type,
        'from_squad_id': p.squad,
        'to_squad_id': type == 'release' ? null : destination,
        'effective_date': DateTime.now().toIso8601String().split('T').first,
        'loan_end_date': loanEnd,
        'reason': reason,
        'requested_by': email,
      }, '${p.name}: $type');
      return;
    }
    final from = p.squad;
    p.squad = type == 'release' ? 'Released' : destination;
    p.role = 'substitute';
    p.onLoan = type == 'loan';
    rosterHistory.insert(
      0,
      '${p.name} · $type · $from → ${p.squad}\n$reason${loanEnd == null ? '' : ' · Returns after $loanEnd'}',
    );
    await save();
    notifyListeners();
  }

  Future<void> addPlayer(String name, String position, String role) async {
    if (!canManage) throw Exception('A club manager is required.');
    if (!online) {
      throw Exception(
        'Reconnect to register a new player. Transfers and loans can be queued offline.',
      );
    }
    players.add(
      PlayerData(
        'p-${DateTime.now().microsecondsSinceEpoch}',
        name,
        position,
        role,
        'Alpha Falcons',
      ),
    );
    rosterHistory.insert(0, '$name · registered · Alpha Falcons');
    await save();
    notifyListeners();
  }

  Future<void> sync() async {
    if (!online || syncing) return;
    syncing = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    for (final action in pending.where((a) => a.status == 'pending').toList()) {
      try {
        final p = action.payload;
        if (action.type == 'score_event') {
          final m = matches.firstWhere((m) => m.id == p['match_id']);
          if (p['type'] == 'compensation') {
            final e = m.events.firstWhere(
              (e) => e.id == p['payload']['compensates'],
            );
            if (e.compensated) {
              throw Exception('The event was already corrected.');
            }
            e.compensated = true;
            e.reason = p['payload']['reason'];
            if (e.team == m.home) {
              m.homeScore -= e.points;
            } else {
              m.awayScore -= e.points;
            }
          } else {
            if (m.status == 'Completed') {
              throw Exception('The match ended before this score could sync.');
            }
            final team = p['payload']['team_id'] as String,
                label = p['payload']['event_type'] as String;
            final option = m.scoringOptions.entries
                .where((e) => e.key.toLowerCase().replaceAll(' ', '_') == label)
                .firstOrNull;
            if (option == null) {
              throw Exception('This scoring event is no longer available.');
            }
            m.events.add(
              ScoreEntry(p['event_id'], team, option.key, option.value),
            );
            if (team == m.home) {
              m.homeScore += option.value;
            } else {
              m.awayScore += option.value;
            }
          }
        } else {
          final player = players.firstWhere((v) => v.id == p['player_id']);
          if (player.squad != p['from_squad_id']) {
            throw Exception('The player has already moved to another squad.');
          }
          player.squad = p['to_squad_id'] ?? 'Released';
          player.role = 'substitute';
          player.onLoan = p['type'] == 'loan';
          rosterHistory.insert(
            0,
            '${player.name} · ${p['type']} · ${p['reason']}',
          );
        }
        action.status = 'applied';
        action.result = 'Applied to the local demo successfully';
      } catch (e) {
        action.status = 'rejected';
        action.result = e.toString().replaceFirst('Exception: ', '');
      }
    }
    syncing = false;
    revision++;
    await save();
    notifyListeners();
  }
}

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: brandInk,
        brightness: Brightness.light,
      ).copyWith(
        primary: brandInk,
        secondary: brandGreen,
        surface: brandCream,
        onSurface: const Color(0xff20291a),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brandCream,
    fontFamily: 'Nunito',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
      ),
      headlineMedium: TextStyle(
        fontSize: 27,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
      ),
      titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      bodyLarge: TextStyle(fontSize: 16),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: brandCream,
      foregroundColor: brandInk,
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xffedf0e7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: brandInk, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      selectedColor: brandGreen.withValues(alpha: .35),
      backgroundColor: Colors.white,
      labelStyle: const TextStyle(
        fontFamily: 'Nunito',
        color: brandInk,
        fontWeight: FontWeight.w700,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: brandInk,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xffe0e6d7)),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: brandGreen.withValues(alpha: .4),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: const StadiumBorder(),
      ),
    ),
  );
}

void openPage(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

void message(BuildContext context, String text) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text.replaceFirst('Exception: ', ''))));
}

String money(int value) => 'PKR ${(value / 100).toStringAsFixed(2)}';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: onPressed == null ? null : brandGradient,
      color: onPressed == null ? Colors.black12 : null,
      borderRadius: BorderRadius.circular(28),
    ),
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 9)],
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    ),
  );
}

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class TeamBadge extends StatelessWidget {
  const TeamBadge({super.key, required this.name, this.size = 44});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: name,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: brandGreen.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(
        name.contains('Falcons')
            ? Icons.sports_soccer
            : name.contains('Kings')
            ? Icons.workspace_premium
            : Icons.shield_outlined,
        size: size * .57,
        color: brandInk,
      ),
    ),
  );
}

class ConnectionStrip extends StatelessWidget {
  const ConnectionStrip({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => Semantics(
      liveRegion: true,
      child: Container(
        color: app.online ? const Color(0xffeaf0dd) : const Color(0xffffeed0),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        child: Row(
          children: [
            Icon(
              app.syncing
                  ? Icons.sync
                  : app.online
                  ? Icons.wifi
                  : Icons.wifi_off,
              size: 14,
              color: brandInk,
            ),
            const SizedBox(width: 7),
            Text(
              app.syncing
                  ? 'Syncing…'
                  : app.online
                  ? 'Online'
                  : 'Offline',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${app.pendingCount} pending · Local demo',
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: brandInk),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: Column(
      children: [
        const ConnectionStrip(),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(subtitle!, style: const TextStyle(color: brandInk)),
            ),
          ),
        Expanded(child: SafeArea(top: false, child: child)),
      ],
    ),
  );
}
