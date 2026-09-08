import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/admin/data/admin_api_response.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';

class AdminConsoleApi {
  const AdminConsoleApi(this.apiClient);

  final ApiClient apiClient;

  Future<AdminConsoleSummary> summary() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/admin/summary',
    );
    return parseSummaryResponse(response.data);
  }

  AdminConsoleSummary parseSummaryResponse(Map<String, dynamic>? body) {
    final data = parseData(body);
    return AdminConsoleSummary.fromJson(data);
  }

  Map<String, dynamic> parseData(Map<String, dynamic>? body) {
    return parseAdminData(
      body,
      defaultErrorCode: 'ADMIN_CONSOLE_ERROR',
      defaultMessage: '管理控制台加载失败',
      invalidDataMessage: '管理控制台响应格式不正确',
    );
  }
}
