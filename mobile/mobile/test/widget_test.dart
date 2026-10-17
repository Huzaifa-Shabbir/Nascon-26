import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/app_state.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('App builds with provider', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const NasconApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(NasconApp), findsOneWidget);
  });
}
