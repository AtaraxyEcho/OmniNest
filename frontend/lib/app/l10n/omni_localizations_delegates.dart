import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/l10n/app_localizations.dart';

/// OmniNest 统一国际化委托列表（适配 Flutter 3.50.1 `material_ui` / `cupertino_ui` 独立包）。
///
/// 合并应用自定义 [AppLocalizations.delegate]、`material_ui` 的
/// [GlobalMaterialLocalizations.delegates] 与 `cupertino_ui` 的
/// [GlobalCupertinoLocalizations.delegate]，彻底消除启动期
/// `MaterialLocalizations` / `CupertinoLocalizations` 不支持 `zh` 的警告。
const List<LocalizationsDelegate<dynamic>> kOmniNestLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      GlobalCupertinoLocalizations.delegate,
    ];
