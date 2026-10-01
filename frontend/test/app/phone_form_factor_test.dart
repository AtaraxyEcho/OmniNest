import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/phone_form_factor.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/admin/application/admin_console_access_provider.dart';

void main() {
  group('resolvePhoneFormFactor 纯函数', () {
    test('手机竖屏与横屏均为手机形态（shortestSide 旋转不变）', () {
      expect(
        resolvePhoneFormFactor(mobilePlatform: true, shortestSide: 390),
        isTrue,
      );
      expect(
        resolvePhoneFormFactor(mobilePlatform: true, shortestSide: 844),
        isFalse,
      );
      // 横屏手机：宽 844 高 390，最短边仍是 390。
      expect(
        resolvePhoneFormFactor(mobilePlatform: true, shortestSide: 390),
        isTrue,
      );
    });

    test('平板与阈值边界不算手机形态', () {
      expect(
        resolvePhoneFormFactor(mobilePlatform: true, shortestSide: 600),
        isFalse,
      );
      expect(
        resolvePhoneFormFactor(mobilePlatform: true, shortestSide: 800),
        isFalse,
      );
    });

    test('非移动平台恒不为手机形态', () {
      expect(
        resolvePhoneFormFactor(mobilePlatform: false, shortestSide: 390),
        isFalse,
      );
    });
  });

  group('DeviceFormFactorListener', () {
    testWidgets('按视口最短边发布手机形态并随 metrics 变化翻转', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: DeviceFormFactorListener(child: const SizedBox.shrink()),
        ),
      );
      expect(container.read(phoneFormFactorProvider), isTrue);

      tester.view.physicalSize = const Size(900, 1280);
      await tester.pump();
      expect(container.read(phoneFormFactorProvider), isFalse);

      tester.view.physicalSize = const Size(780, 360);
      await tester.pump();
      expect(container.read(phoneFormFactorProvider), isTrue);
    });

    testWidgets('桌面平台窄视口也不算手机形态', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: DeviceFormFactorListener(child: const SizedBox.shrink()),
        ),
      );
      expect(container.read(phoneFormFactorProvider), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  group('canAccessAdminConsoleProvider 手机形态收敛', () {
    Future<ProviderContainer> buildContainer({
      required bool phoneFormFactor,
      required String role,
    }) async {
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _RoleAuthSessionNotifier(role),
          ),
          phoneFormFactorProvider.overrideWith(
            () => _StubPhoneFormFactor(phoneFormFactor),
          ),
        ],
      );
      await container.read(authSessionProvider.future);
      return container;
    }

    test('管理员在手机形态不可达，平板形态可达', () async {
      final phone = await buildContainer(phoneFormFactor: true, role: 'ADMIN');
      addTearDown(phone.dispose);
      expect(phone.read(canAccessAdminConsoleProvider), isFalse);

      final tablet = await buildContainer(
        phoneFormFactor: false,
        role: 'ADMIN',
      );
      addTearDown(tablet.dispose);
      expect(tablet.read(canAccessAdminConsoleProvider), isTrue);
    });

    test('无管理权限用户在平板形态仍不可达', () async {
      final tablet = await buildContainer(
        phoneFormFactor: false,
        role: 'MEMBER',
      );
      addTearDown(tablet.dispose);
      expect(tablet.read(canAccessAdminConsoleProvider), isFalse);
    });
  });

  // 路由侧的布尔决策由 router_auth_guard_test 覆盖；headless 容器中
  // go_router 不会评估 redirect（无 Router 挂载），端到端重定向留实机验收。
}

class _StubPhoneFormFactor extends PhoneFormFactorNotifier {
  _StubPhoneFormFactor(this.value);

  final bool value;

  @override
  bool build() => value;
}

class _RoleAuthSessionNotifier extends AuthSessionNotifier {
  _RoleAuthSessionNotifier(this.role);

  final String role;

  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(
      user: UserProfile(id: 'user-1', username: 'user', role: role),
    );
  }
}
