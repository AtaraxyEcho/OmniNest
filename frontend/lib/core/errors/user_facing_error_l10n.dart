import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/error_code_l10n.dart';
import 'package:omninest/core/errors/error_message.dart';

/// 将 application 层写入状态的错误文案重新映射为当前语言。
///
/// application 无 BuildContext 时可能写入错误码；有 l10n 时优先按码翻译。
extension UserFacingErrorL10n on AppLocalizations {
  String localizeStoredError(String raw) {
    if (raw.isEmpty) {
      return errorOperationFailed;
    }
    return messageForErrorCode(raw, fallback: raw);
  }

  String localizeUserFacing(UserFacingError error) {
    final code = error.code;
    if (code != null && code.isNotEmpty) {
      return messageForErrorCode(code, fallback: error.message);
    }
    return localizeStoredError(error.message);
  }
}
