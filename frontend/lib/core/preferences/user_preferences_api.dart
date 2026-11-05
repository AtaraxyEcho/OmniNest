import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/envelope_guard.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/network/capability_gate_interceptor.dart';
import 'package:omninest/core/preferences/preference_snapshot.dart';

class UserPreferencesApi {
  const UserPreferencesApi(this.apiClient);

  final ApiClient apiClient;

  /// 当前会话是否可维护本人偏好（远端同步）。
  bool get canWritePreferences =>
      apiClient.hasPermission(preferenceWritePermission);

  Future<PreferenceSnapshot> getSnapshot(String scope) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/preferences/$scope',
    );
    final data = _parseData(response.data);
    if (data == null) {
      return PreferenceSnapshot.empty(scope);
    }
    return PreferenceSnapshot.fromJson(data);
  }

  Future<PreferenceSnapshot> patch({
    required String scope,
    required int? baseVersion,
    required Map<String, dynamic> changes,
    Set<String> removeKeys = const {},
  }) async {
    final response = await apiClient.dio.patch<Map<String, dynamic>>(
      '/preferences/$scope',
      data: {
        'baseVersion': baseVersion,
        'changes': changes,
        'removeKeys': removeKeys.toList()..sort(),
      },
    );
    final data = _parseData(response.data);
    if (data == null) {
      throw const AppException(
        code: 'PREFERENCE_RESPONSE_INVALID',
        message: '用户偏好响应格式不正确',
      );
    }
    return PreferenceSnapshot.fromJson(data);
  }

  Future<void> delete({required String scope, required int baseVersion}) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/preferences/$scope',
      queryParameters: {'baseVersion': baseVersion},
    );
    _parseEnvelope(response.data);
  }

  Map<String, dynamic> _parseEnvelope(Map<String, dynamic>? body) {
    // 网关空响应或非信封 JSON 一律视为失败：把 {} 当成"偏好已被清空"
    // 会覆盖本地缓存里正常快照（随后又被同步回写，等于用户偏好被抹掉）。
    ensureEnvelopeSuccess(body, fallbackMessage: '偏好设置请求失败');
    return body!;
  }

  Map<String, dynamic>? _parseData(Map<String, dynamic>? body) {
    final envelope = _parseEnvelope(body);
    final data = envelope['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }
}
