import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/core.dart';
import 'package:mobile/main.dart';
import 'package:mobile/screens/sports.dart';
import 'package:mobile/screens/store.dart';
import 'package:mobile/screens/club.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await app.init();
    app.role = 'super_admin';
    app.online = true;
    app.cart.clear();
    app.pending.clear();
  });
  test('Checkout failure preserves stock; successful discounted order is persistent', () async {
    final state = AppState();
    await state.init();
    final product = state.products.first;
    state.addCart(product, 'M');
    final before = product.stock;
    await expectLater(state.checkout('tok_declined', ''), throwsException);
    expect(product.stock, before);
    expect(state.cartCount, 1);
    final order = await state.checkout('tok_success', 'WELCOME10');
    expect(order.total, 405000);
    expect(product.stock, before - 1);
    expect(state.cartCount, 0);
    final restored = AppState();
    await restored.init();
    expect(restored.orders.first.id, order.id);
    expect(restored.products.first.stock, before - 1);
  });
  test('Offline action survives restart and sync applies once', () async {
    final state = AppState();
    await state.init();
    state.role = 'league_organizer';
    state.online = false;
    final before = state.matches.first.homeScore;
    state.addScore(state.matches.first, state.matches.first.home, 'Goal', 1);
    await state.save();
    expect(state.matches.first.homeScore, before);
    expect(state.pendingCount, 1);
    final restored = AppState();
    await restored.init();
    restored.online = true;
    await restored.sync();
    expect(restored.matches.first.homeScore, before + 1);
    expect(restored.pendingCount, 0);
    await restored.sync();
    expect(restored.matches.first.homeScore, before + 1);
  });
  test('Score compensation is append neutral and role protected', () async {
    final state = AppState();
    await state.init();
    state.role = 'league_organizer';
    final m = state.matches.first;
    final before = m.homeScore;
    state.addScore(m, m.home, 'Goal', 1);
    final entry = m.events.last;
    state.compensate(m, entry, reason: 'Offside');
    expect(m.homeScore, before);
    expect(entry.compensated, isTrue);
    expect(entry.reason, 'Offside');
    state.compensate(m, entry);
    expect(m.homeScore, before);
    state.role = 'viewer';
    expect(() => state.addScore(m, m.home, 'Goal', 1), throwsException);
  });
  for (final size in [const Size(360, 640), const Size(640, 360)]) {
    testWidgets('All core screens render without overflow at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final screens = <Widget>[
        const LoginScreen(),
        Dashboard(onTab: (_) {}),
        const FixturesScreen(),
        MatchDetailScreen(match: app.matches.first),
        const StandingsScreen(),
        const ClubScreen(),
        const RosterScreen(),
        const StoreScreen(),
        ProductScreen(product: app.products.first),
        const CartScreen(),
        const ProfileScreen(),
        const SyncScreen(),
        const SettingsScreen(),
        ScoringScreen(match: app.matches.first),
      ];
      for (final screen in screens) {
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(),
              home: screen,
            ),
          ),
        );
        await tester.runAsync(() async {
          final context = tester.element(find.byType(MaterialApp));
          await precacheImage(
            const AssetImage('assets/sports-mascot.png'),
            context,
          );
          if (context.mounted) {
            await precacheImage(
              const AssetImage('assets/falcons-jersey.png'),
              context,
            );
          }
        });
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${screen.runtimeType} at $size',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }
}
