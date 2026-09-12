import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/setup/data/initial_setup_api.dart';
import 'package:omninest/features/setup/domain/initial_setup_status.dart';

final initialSetupApiProvider = Provider<InitialSetupApi>((ref) {
  return InitialSetupApi(ref.watch(apiClientProvider));
});

final initialSetupProvider =
    AsyncNotifierProvider<InitialSetupController, InitialSetupStatus>(
      InitialSetupController.new,
    );

class InitialSetupController extends AsyncNotifier<InitialSetupStatus> {
  @override
  Future<InitialSetupStatus> build() {
    return ref.watch(initialSetupApiProvider).status();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(ref.read(initialSetupApiProvider).status);
  }

  /// 生成安装向导两步验证秘钥。
  Future<TwoFactorSetupData> newTwoFactorSecret({String? username}) {
    return ref
        .read(initialSetupApiProvider)
        .newTwoFactorSecret(username: username);
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
