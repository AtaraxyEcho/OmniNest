import 'package:flutter/material.dart';
import 'package:omninest/features/portal/domain/portal_focus_models.dart';

/// Portal 焦点图标的 Material 映射。
extension PortalFocusIconPresentation on PortalFocusIcon {
  /// 返回当前图标语义对应的 Material 图标。
  IconData get iconData => switch (this) {
    PortalFocusIcon.reader => Icons.menu_book_rounded,
    PortalFocusIcon.video => Icons.movie_rounded,
    PortalFocusIcon.photos => Icons.photo_library_rounded,
    PortalFocusIcon.music => Icons.music_note_rounded,
  };
}
