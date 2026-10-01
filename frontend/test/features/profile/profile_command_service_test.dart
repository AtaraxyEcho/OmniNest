import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/profile/domain/profile_repository.dart';
import 'package:omninest/features/profile/domain/user_session.dart';
import 'package:omninest/features/profile/presentation/widgets/change_password_dialog.dart';

void main() {
  test('个人资料应用服务转发写操作', () async {
    final repository = _FakeProfileRepository();
    final service = ProfileCommandService(repository);

    await service.uploadAvatar(Uint8List.fromList([1, 2, 3]), 'avatar.png');
    await service.changePassword(
      oldPassword: 'current-password',
      newPassword: 'new-password',
    );
    await service.updateProfile(
      displayName: 'New Name',
      email: 'new@example.com',
    );
    await service.revokeSession('session-1');

    expect(repository.uploadedFileName, 'avatar.png');
    expect(repository.oldPassword, 'current-password');
    expect(repository.newPassword, 'new-password');
    expect(repository.updatedDisplayName, 'New Name');
    expect(repository.updatedEmail, 'new@example.com');
    expect(repository.revokedSessionId, 'session-1');
  });

  testWidgets('修改密码失败时由对话框展示反馈', (tester) async {
    final repository = _FakeProfileRepository(changePasswordFails: true);
    final service = ProfileCommandService(repository);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [profileCommandServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const Scaffold(body: ChangePasswordDialog()),
        ),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'current-password');
    await tester.enterText(fields.at(1), 'new-password');
    await tester.enterText(fields.at(2), 'new-password');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(repository.oldPassword, 'current-password');
    expect(find.textContaining('修改失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // 失败反馈走 toast（自带 2 秒自动关闭计时器），断言完成后在虚拟
    // 时间轴上排干该计时器，避免测试结束时的 pending timer 断言。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({this.changePasswordFails = false});

  final bool changePasswordFails;
  String? uploadedFileName;
  String? oldPassword;
  String? newPassword;
  String? updatedDisplayName;
  String? updatedEmail;
  String? revokedSessionId;

  @override
  Future<String> uploadAvatar(Uint8List bytes, String fileName) async {
    uploadedFileName = fileName;
    return 'https://example.test/avatar.png';
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    this.oldPassword = oldPassword;
    this.newPassword = newPassword;
    if (changePasswordFails) {
      throw Exception('change-password-failed');
    }
  }

  @override
  Future<void> updateProfile({String? displayName, String? email}) async {
    updatedDisplayName = displayName;
    updatedEmail = email;
  }

  @override
  Future<List<UserSession>> getSessions() async => const <UserSession>[];

  @override
  Future<void> revokeSession(String sessionId) async {
    revokedSessionId = sessionId;
  }
}
