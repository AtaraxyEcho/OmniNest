import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_highlight_color_bar.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';

/// 阅读器统一选区浮动工具条（v3：1:1 对齐样例 `.sel-pop`，脱离系统外壳彻底根除底部黑底）。
class ReaderSelectionColorToolbar extends StatefulWidget {
  const ReaderSelectionColorToolbar({
    required this.anchors,
    required this.selectedColor,
    required this.onSelectColor,
    required this.addAnnotationLabel,
    required this.copyLabel,
    required this.selectAllLabel,
    required this.onCopy,
    this.onSelectAll,
    this.onSubmitInlineNote,
    this.onAnnotate,
    this.removeHighlightLabel,
    this.onRemoveHighlight,
    this.highlightEnabled = true,
    this.contextMenuButtonItems = const [],
    super.key,
  });

  final TextSelectionToolbarAnchors anchors;
  final String? selectedColor;
  final ValueChanged<String> onSelectColor;
  final String addAnnotationLabel;
  final String copyLabel;
  final String selectAllLabel;
  final VoidCallback onCopy;
  final VoidCallback? onSelectAll;
  final ValueChanged<String>? onSubmitInlineNote;
  final VoidCallback? onAnnotate;
  final String? removeHighlightLabel;
  final VoidCallback? onRemoveHighlight;
  final bool highlightEnabled;
  final List<ContextMenuButtonItem> contextMenuButtonItems;

  @override
  State<ReaderSelectionColorToolbar> createState() =>
      _ReaderSelectionColorToolbarState();
}

class _ReaderSelectionColorToolbarState
    extends State<ReaderSelectionColorToolbar> {
  bool _noting = false;
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submitNote() {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    widget.onSubmitInlineNote?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    final anchor = widget.anchors.primaryAnchor;
    final secondaryAnchor = widget.anchors.secondaryAnchor ?? anchor;

    return CustomSingleChildLayout(
      delegate: _SelectionPopoverLayoutDelegate(
        primaryAnchor: anchor,
        secondaryAnchor: secondaryAnchor,
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.92, end: 1.0),
        duration: MotionToken.reduced(
          context,
          const Duration(milliseconds: 180),
        ),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: child,
          );
        },
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            decoration: BoxDecoration(
              color: ReaderReadingPalette.selectionToolbarSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.48),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: EdgeInsets.symmetric(
              horizontal: _noting ? 10 : 8,
              vertical: _noting ? 10 : 6,
            ),
            child: _noting ? _buildInlineNoteBox() : _buildActionRow(),
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.highlightEnabled) ...[
          ReaderHighlightColorBar(
            selectedColor: widget.selectedColor,
            onSelect: widget.onSelectColor,
          ),
          _divider(),
        ],
        if (widget.onRemoveHighlight != null &&
            widget.removeHighlightLabel != null)
          _SelActionButton(
            icon: Icons.format_color_reset_rounded,
            label: widget.removeHighlightLabel!,
            onPressed: widget.onRemoveHighlight!,
          ),
        if (widget.highlightEnabled &&
            (widget.onSubmitInlineNote != null || widget.onAnnotate != null))
          _SelActionButton(
            icon: Icons.edit_outlined,
            label: widget.addAnnotationLabel,
            onPressed: () {
              if (widget.onSubmitInlineNote != null) {
                setState(() => _noting = true);
              } else {
                widget.onAnnotate?.call();
              }
            },
          ),
        _SelActionButton(
          icon: Icons.copy_rounded,
          label: widget.copyLabel,
          onPressed: widget.onCopy,
        ),
        if (widget.onSelectAll != null)
          _SelActionButton(
            icon: Icons.select_all_rounded,
            label: widget.selectAllLabel,
            onPressed: widget.onSelectAll!,
          ),
      ],
    );
  }

  Widget _buildInlineNoteBox() {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: 280,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _submitNote,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true):
              _submitNote,
          const SingleActivator(LogicalKeyboardKey.escape):
              () => setState(() => _noting = false),
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _noteController,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5, // ignore: font_size_whitelist
                height: 1.45,
              ),
              decoration: InputDecoration(
                hintText: l10n.readerInlineNoteHint,
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13, // ignore: font_size_whitelist
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(
                    color: ReaderReadingPalette.selectionToolbarAccent,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SelActionButton(
                  label: l10n.coreCancel,
                  onPressed: () => setState(() => _noting = false),
                ),
                const SizedBox(width: 4),
                _SelActionButton(
                  label: l10n.readerSaveAnnotation,
                  accent: true,
                  enabled: _noteController.text.trim().isNotEmpty,
                  onPressed: _submitNote,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: Colors.white.withValues(alpha: 0.18),
  );
}

class _SelectionPopoverLayoutDelegate extends SingleChildLayoutDelegate {
  const _SelectionPopoverLayoutDelegate({
    required this.primaryAnchor,
    required this.secondaryAnchor,
  });

  final Offset primaryAnchor;
  final Offset secondaryAnchor;

  static const double _screenMargin = 12.0;
  static const double _verticalGap = 10.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final idealX = primaryAnchor.dx - childSize.width / 2;
    final maxX = math.max(
      _screenMargin,
      size.width - childSize.width - _screenMargin,
    );
    final double x = idealX.clamp(_screenMargin, maxX);

    final aboveY = primaryAnchor.dy - childSize.height - _verticalGap;
    final belowY = secondaryAnchor.dy + _verticalGap + 18;
    // 避让顶部 64px 阅读器顶栏，选中页面最顶行时自动翻转到选区下方
    const topClearance = 68.0;
    final double y =
        aboveY >= topClearance
            ? aboveY
            : belowY
                .clamp(
                  _screenMargin,
                  math.max(
                    _screenMargin,
                    size.height - childSize.height - _screenMargin,
                  ),
                )
                .toDouble();
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_SelectionPopoverLayoutDelegate oldDelegate) =>
      oldDelegate.primaryAnchor != primaryAnchor ||
      oldDelegate.secondaryAnchor != secondaryAnchor;
}

class _SelActionButton extends StatefulWidget {
  const _SelActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.accent = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool accent;
  final bool enabled;

  @override
  State<_SelActionButton> createState() => _SelActionButtonState();
}

class _SelActionButtonState extends State<_SelActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fg =
        !widget.enabled
            ? Colors.white.withValues(alpha: 0.35)
            : widget.accent
            ? ReaderReadingPalette.selectionToolbarAccent
            : Colors.white;
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onPressed : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color:
                _hovered && widget.enabled
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 14, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5, // ignore: font_size_whitelist
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
