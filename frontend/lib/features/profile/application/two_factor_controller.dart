import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/profile/data/me_api.dart';

/// 两步验证的应用层入口。
final twoFactorControllerProvider = Provider<TwoFactorController>((ref) {
  return TwoFactorController(ref.watch(meApiProvider));
});

/// 协调两步验证的状态查询与开启/关闭流程。
///
/// presentation 只描述步骤与错误展示，具体端点、请求体与网络异常都留在这一层，
/// 避免安全相关调用的判据分散在页面里。
class TwoFactorController {
  const TwoFactorController(this._api);

  final MeApi _api;

  Future<TwoFactorStatusData> status() => _api.twoFactorStatus();

  Future<TwoFactorSetupData> setup({required String password}) {
    return _api.twoFactorSetup(password: password);
  }

  Future<List<String>> enable({required String code}) {
    return _api.twoFactorEnable(code: code);
  }

  Future<void> disable({required String password, required String code}) {
    return _api.twoFactorDisable(password: password, code: code);
  }
}
