import 'package:flutter/widgets.dart' show Locale;
import 'package:omninest/app/l10n/app_localizations.dart';

/// 进程级 UI 语言镜像，供没有 `BuildContext` 的层解析可直接展示的文案。
///
/// 控制器（Riverpod Notifier、导入队列、扫描任务等）把错误写进
/// `state.errorMessage` 这类纯字符串字段，拿不到 `AppLocalizations.of(context)`。
/// 没有镜像时它们只能保留服务端原文——中文后端的文案在英文界面里会原样透出。
/// [LocaleController] 在语言确定与切换时写入这里，控制器层据此解析文案。
abstract final class UserFacingErrorLocale {
  static const Set<String> _supportedLanguageCodes = {'zh', 'en'};

  static String _languageCode = 'zh';
  static AppLocalizations? _cached;

  /// 当前生效的语言码。
  static String get languageCode => _languageCode;

  /// 绑定当前 UI 语言；不支持的语言码保持上一次的取值。
  static void bind(String? languageCode) {
    if (languageCode == null ||
        !_supportedLanguageCodes.contains(languageCode) ||
        languageCode == _languageCode) {
      return;
    }
    _languageCode = languageCode;
    _cached = null;
  }

  /// 解析当前语言对应的本地化实例。
  static AppLocalizations resolve() =>
      _cached ??= lookupAppLocalizations(Locale(_languageCode));
}
