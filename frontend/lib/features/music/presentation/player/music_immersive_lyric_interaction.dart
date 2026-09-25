part of 'music_immersive_lyrics.dart';

/// 键盘快捷键与歌词行菜单。
extension _MusicImmersiveLyricInteraction on _MusicImmersiveLyricsState {
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final last = widget.lyrics.length - 1;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      widget.onTogglePlayback();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onPrevious();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onNext();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _seekTo((_activeIndex - 1).clamp(0, last));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _seekTo((_activeIndex + 1).clamp(0, last));
      return KeyEventResult.handled;
    }
    // Home/End 跳首末句，PageUp/PageDown 按页（±5 句）跳转。
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _seekTo(0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _seekTo(last);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _seekTo((_activeIndex - _pageStep).clamp(0, last));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _seekTo((_activeIndex + _pageStep).clamp(0, last));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 长按/右键行菜单：复制该行歌词与歌词延迟微调（±0.1s，写入曲目级覆盖），
  Future<void> _showLineMenu(int index, Offset globalPosition) async {
    if (index < 0 || index >= widget.lyrics.length) {
      return;
    }
    final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlay is! RenderBox) {
      return;
    }
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (l10n == null) {
      return;
    }
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: _lineMenuCopy,
          child: Text(l10n.musicLyricCopyLine),
        ),
        PopupMenuItem(
          value: _lineMenuDelayLater,
          child: Text(l10n.musicLyricDelayLater),
        ),
        PopupMenuItem(
          value: _lineMenuAdvanceEarlier,
          child: Text(l10n.musicLyricAdvanceEarlier),
        ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _lineMenuCopy:
        _copyLine(index);
      case _lineMenuDelayLater:
        widget.onAdjustLyricOffset?.call(100);
      case _lineMenuAdvanceEarlier:
        widget.onAdjustLyricOffset?.call(-100);
    }
  }

  /// 复制一行歌词到剪贴板，并在宿主提供 ScaffoldMessenger 时给出反馈。
  void _copyLine(int index) {
    if (index < 0 || index >= widget.lyrics.length) {
      return;
    }
    unawaited(
      Clipboard.setData(ClipboardData(text: widget.lyrics[index].text)),
    );
    // 复制反馈用宿主提供的本地化文案；没有本地化委派的宿主（部分测试）
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (l10n == null || messenger == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.musicLyricCopied),
          duration: const Duration(seconds: 2),
        ),
      );
  }
}
