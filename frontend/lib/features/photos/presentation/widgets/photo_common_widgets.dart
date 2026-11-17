import 'package:flutter/material.dart';

import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/photos/application/photo_center_models.dart';
import 'package:omninest/features/photos/domain/photo_group.dart';

/// 将导入流程提示映射为当前语言的文案。
String photoImportNoticeText(
  AppLocalizations l10n,
  PhotoImportNotice notice, {
  String? detail,
}) {
  if (notice == PhotoImportNotice.backendFailed &&
      detail != null &&
      detail.trim().isNotEmpty) {
    return detail;
  }
  return switch (notice) {
    PhotoImportNotice.completedNotVisible =>
      l10n.photosImportCompletedNotVisible,
    PhotoImportNotice.stillProcessing => l10n.photosImportStillProcessing,
    PhotoImportNotice.backendFailed => l10n.photosImportBackendFailed,
  };
}

/// 分组维度标签。
String photoGroupByLabel(AppLocalizations l10n, GroupBy by) {
  return switch (by) {
    GroupBy.date => l10n.photosGroupByDate,
    GroupBy.location => l10n.photosGroupByLocation,
    GroupBy.format => l10n.photosGroupByFormat,
    GroupBy.tag => l10n.photosGroupByTag,
  };
}

/// 持有并释放对话框文本控制器的轻量包装。
///
/// 控制器在对话框 Widget 从树中移除（含退出动画结束）后释放，
/// 调用方须在对话框树内读取文本，不要在 [showDialog] 返回后再访问。
class PhotoDialogTextField extends StatefulWidget {
  const PhotoDialogTextField({
    required this.builder,
    this.initialText,
    super.key,
  });

  final String? initialText;
  final Widget Function(BuildContext context, TextEditingController controller)
  builder;

  @override
  State<PhotoDialogTextField> createState() => _PhotoDialogTextFieldState();
}

class _PhotoDialogTextFieldState extends State<PhotoDialogTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
