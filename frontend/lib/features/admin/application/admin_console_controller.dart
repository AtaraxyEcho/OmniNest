import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/admin/data/admin_console_api.dart';
import 'package:omninest/features/admin/domain/admin_console_summary.dart';

final adminConsoleApiProvider = Provider<AdminConsoleApi>((ref) {
  return AdminConsoleApi(ref.watch(apiClientProvider));
});

final adminConsoleControllerProvider =
    AsyncNotifierProvider<AdminConsoleController, AdminConsoleSummary>(
      AdminConsoleController.new,
    );

class AdminConsoleController extends AsyncNotifier<AdminConsoleSummary> {
  AdminConsoleApi get _api => ref.read(adminConsoleApiProvider);

  @override
  Future<AdminConsoleSummary> build() {
    ref.watch(sessionEpochProvider);
    return _api.summary();
  }

  Future<void> refreshSummary() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_api.summary);
  }
}
