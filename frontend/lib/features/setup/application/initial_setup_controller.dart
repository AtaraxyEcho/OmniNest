import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/utils/bounded_async_step.dart';
import 'package:omninest/features/setup/data/initial_setup_api.dart';
import 'package:omninest/features/setup/domain/initial_setup_status.dart';

final initialSetupApiProvider = Provider<InitialSetupApi>((ref) {
  return InitialSetupApi(ref.watch(apiClientProvider));
});

final initialSetupProvider =
    AsyncNotifierProvider<InitialSetupController, InitialSetupStatus>(
      InitialSetupController.new,
    );

/// 启动期安装状态探测预算：后端不可达时 Dio 的 10s 连接 + 30s 接收超时
/// 叠加两次重试会把 /boot 拖到一分半以上。超时落地为 AsyncError，
/// isLoading 变 false，redirect 自动放行到可交互页面；与「无需安装」的
/// 语义区别开，后端恢复后在登录/服务器设置页重试即可。
const Duration _setupProbeBudget = Duration(seconds: 6);

class InitialSetupController extends AsyncNotifier<InitialSetupStatus> {
  @override
  Future<InitialSetupStatus> build() {
    final api = ref.watch(initialSetupApiProvider);
    return boundedAsyncStep(ref, api.status(), _setupProbeBudget);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(ref.read(initialSetupApiProvider).status);
  }

  /// 生成安装向导两步验证秘钥。
  Future<TwoFactorSetupData> newTwoFactorSecret({
    required String setupToken,
    String? username,
  }) {
    return ref
        .read(initialSetupApiProvider)
        .newTwoFactorSecret(setupToken: setupToken, username: username);
  }

  /// 创建超管；要求两步验证时返回一次性备份码，否则返回 null。
  Future<List<String>?> createSuperAdmin({
    required String setupToken,
    required String username,
    required String displayName,
    required String email,
    required String password,
    required String instanceName,
    required String defaultLocale,
    required String defaultTimezone,
    String? totpSecret,
    String? totpCode,
  }) {
    return ref
        .read(initialSetupApiProvider)
        .createSuperAdmin(
          setupToken: setupToken,
          username: username,
          displayName: displayName,
          email: email,
          password: password,
          instanceName: instanceName,
          defaultLocale: defaultLocale,
          defaultTimezone: defaultTimezone,
          totpSecret: totpSecret,
          totpCode: totpCode,
        );
  }
}
