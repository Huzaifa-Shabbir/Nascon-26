import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/api.dart';

void main() {
  test('friendlyError maps known backend codes', () {
    expect(
      friendlyError(ApiException('x', code: 'OUT_OF_STOCK', statusCode: 409)),
      'That item just sold out.',
    );
    expect(
      friendlyError(ApiException('x', code: 'UNAUTHENTICATED', statusCode: 401)),
      'Please sign in again.',
    );
    expect(
      friendlyError(ApiException('bad', code: 'VALIDATION_ERROR', fields: ['payment.token'])),
      'Please check: payment.token',
    );
  });

  test('friendlyError handles network-ish messages', () {
    expect(
      friendlyError(Exception('SocketException: Connection refused')),
      contains('Cannot reach the server'),
    );
  });
}
