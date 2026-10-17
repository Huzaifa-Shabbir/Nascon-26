import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/api.dart';
import 'package:mobile/app_state.dart';

void main() {
  test('AppState role helpers match demo accounts', () {
    expect(AppState.demoLeagueId, 'lg-mobile-1');
    expect(AppState.rosterLeagueId, 'lg-r1');
  });

  test('ApiException carries status and fields', () {
    final e = ApiException(
      'bad',
      code: 'VALIDATION_ERROR',
      statusCode: 400,
      fields: ['email'],
    );
    expect(e.statusCode, 400);
    expect(friendlyError(e), 'Please check: email');
  });
}
