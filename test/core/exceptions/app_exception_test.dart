import 'package:flutter_test/flutter_test.dart';
import 'package:veyra/core/exceptions/app_exception.dart';

void main() {
  group('AppException', () {
    group('Factory constructors', () {
      test('network creates exception with correct type', () {
        final exception = AppException.network(
          '网络错误',
          details: 'timeout',
        );

        expect(exception.type, ExceptionType.network);
        expect(exception.message, '网络错误');
        expect(exception.details, 'timeout');
      });

      test('authentication creates exception with correct type', () {
        final exception = AppException.authentication(
          'API Key 无效',
          details: 'expired',
        );

        expect(exception.type, ExceptionType.authentication);
        expect(exception.message, 'API Key 无效');
        expect(exception.details, 'expired');
      });

      test('packNotFound creates exception with packId in message', () {
        final exception = AppException.packNotFound('test_pack');

        expect(exception.type, ExceptionType.packNotFound);
        expect(exception.message, contains('test_pack'));
      });

      test('parseError creates exception with correct type', () {
        final exception = AppException.parseError(
          '解析失败',
          details: 'invalid JSON',
        );

        expect(exception.type, ExceptionType.parseError);
        expect(exception.message, '解析失败');
        expect(exception.details, 'invalid JSON');
      });

      test('domainNotAllowed includes domain and allowed list', () {
        final exception = AppException.domainNotAllowed(
          'evil.com',
          ['good.com', 'safe.org'],
        );

        expect(exception.type, ExceptionType.domainNotAllowed);
        expect(exception.message, contains('evil.com'));
        expect(exception.details, contains('good.com'));
        expect(exception.details, contains('safe.org'));
      });

      test('unknown creates exception with original error', () {
        final originalError = Exception('original');
        final exception = AppException.unknown(
          '未知错误',
          error: originalError,
        );

        expect(exception.type, ExceptionType.unknown);
        expect(exception.message, '未知错误');
        expect(exception.originalError, originalError);
      });
    });

    group('getUserMessage', () {
      test('network returns user-friendly message', () {
        final exception = AppException.network('internal error');
        expect(exception.getUserMessage(), contains('网络'));
      });

      test('authentication returns user-friendly message', () {
        final exception = AppException.authentication('invalid');
        expect(exception.getUserMessage(), contains('API Key'));
      });

      test('packNotFound returns original message', () {
        final exception = AppException.packNotFound('my_pack');
        expect(exception.getUserMessage(), contains('my_pack'));
      });

      test('parseError returns user-friendly message', () {
        final exception = AppException.parseError('bad JSON');
        expect(exception.getUserMessage(), contains('解析'));
      });

      test('domainNotAllowed returns the domain in message', () {
        final exception = AppException.domainNotAllowed('bad.com', ['good.com']);
        expect(exception.getUserMessage(), contains('bad.com'));
      });

      test('unknown includes original message', () {
        final exception = AppException.unknown('something went wrong');
        expect(exception.getUserMessage(), contains('something went wrong'));
      });
    });

    group('toString', () {
      test('includes type, message, and details', () {
        final exception = AppException(
          type: ExceptionType.network,
          message: 'Test error',
          details: 'Additional info',
        );

        final str = exception.toString();
        expect(str, contains('network'));
        expect(str, contains('Test error'));
        expect(str, contains('Additional info'));
      });

      test('includes original error when present', () {
        final originalError = Exception('root cause');
        final exception = AppException(
          type: ExceptionType.unknown,
          message: 'Wrapper',
          originalError: originalError,
        );

        final str = exception.toString();
        expect(str, contains('root cause'));
      });
    });
  });
}
