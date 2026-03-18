import 'package:flutter_test/flutter_test.dart';

import 'package:ccpocket/utils/structured_error_inference.dart';

void main() {
  group('inferStructuredErrorCode', () {
    test('does not classify guidance text as auth error', () {
      final code = inferStructuredErrorCode(
        message:
            '提案:\n'
            '1. `claude` を起動\n'
            '2. 必要なら `claude auth login` を実行\n'
            '3. `/login` の遠隔ログインを主役にする',
      );

      expect(code, isNull);
    });
  });
}
