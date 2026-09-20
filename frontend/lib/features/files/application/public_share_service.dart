import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/features/files/data/share_api.dart';
import 'package:omninest/features/files/domain/public_share.dart';

/// 公开分享页面使用的应用服务。
class PublicShareService {
  const PublicShareService(this._repository);

  final PublicShareRepository _repository;

  Future<SharePreviewResult> preview(String token, {String? password}) {
    return _repository.preview(token, password: password);
  }

  Future<ShareAcceptResult> accept(
    String token, {
    String? password,
    String? authToken,
  }) {
    return _repository.accept(token, password: password, authToken: authToken);
  }
}

/// 公开分享应用服务依赖注入入口。
final publicShareServiceProvider = Provider<PublicShareService>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  if (environment == null) {
    throw StateError('服务器地址未配置');
  }
  final api = ShareApi(environment.apiBaseUrl);
  ref.onDispose(api.close);
  return PublicShareService(api);
});
