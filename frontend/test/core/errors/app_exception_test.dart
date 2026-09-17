import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_message.dart';

void main() {
  test('AppException.toString 仅输出用户文案，不泄漏结构与错误码', () {
    const error = AppException(
      code: '400',
      message: '密码不能使用常见弱口令或与用户名相同',
    );
    expect(error.toString(), '密码不能使用常见弱口令或与用户名相同');
    expect(error.toString(), isNot(contains('AppException')));
    expect(error.toString(), isNot(contains('400')));
  });

  test('describeUserFacingError 无 l10n 时优先 message', () {
    const error = AppException(
      code: '400',
      message: '密码不能使用常见弱口令或与用户名相同',
    );
    final described = describeUserFacingError(error);
    expect(described.message, '密码不能使用常见弱口令或与用户名相同');
  });
}
