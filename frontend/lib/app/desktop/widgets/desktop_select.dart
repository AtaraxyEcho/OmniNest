import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_motion.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/app/theme/desktop/desktop_type.dart';
import 'package:omninest/core/theme/motion_token.dart';

/// 桌面下拉（样例 `Select.tsx`）：替代原生 `DropdownButton`，因为系统菜单
/// 不认设计令牌。三档外观 field / small / pill；选项多于 12 个时自动带搜索，
/// 空间不足时向上翻转。
class DesktopSelectOption<T> {
  const DesktopSelectOption({
    required this.value,
    required this.label,
    this.hint,
  });

  final T value;
  final String label;

  /// 右侧附注（样例 `.dd-opt small`）：11.5 / text3 / tabular-nums。
  final String? hint;
}

enum DesktopSelectVariant { field, small, pill }

/// 弹层相对触发器的水平基准（样例 `Select.tsx` 的 `align`）。
///
/// `end` 让弹层右缘贴住触发器右缘；两种取值都会被钳进视口 8px 内边距，
/// 页面右缘的 select 因此不会把面板顶出屏幕。
enum DesktopSelectAlign { start, end }

class DesktopSelect<T> extends StatefulWidget {
  const DesktopSelect({
    required this.value,
    required this.options,
    required this.onChanged,
    this.variant = DesktopSelectVariant.field,
    this.search,
    this.width,
    this.placeholder,
    this.keyName,
    this.icon,
    this.invalid = false,
    this.align = DesktopSelectAlign.start,
    super.key,
  });

  final T value;
  final List<DesktopSelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final DesktopSelectVariant variant;

  /// null 时按选项数自动决定（> 12 可搜索）。
  final bool? search;
  final double? width;
  final String? placeholder;
  final String? keyName;

  /// 触发器前导图标（样例 `.dd` 的 `gap: 8`）。
  final IconData? icon;

  /// 样例 `.dd-field.bad`：描边换成错误色 `#e57a74`。
  final bool invalid;

  final DesktopSelectAlign align;

  @override
  State<DesktopSelect<T>> createState() => _DesktopSelectState<T>();
}

class _DesktopSelectState<T> extends State<DesktopSelect<T>> {
  final LayerLink _link = LayerLink();
  final TextEditingController _search = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'desktop select');
  // 面板自身与搜索框各持一个焦点点：键盘打开时触发器仍握着焦点，
  // `autofocus` 会因 `scope.focusedChild != null` 被丢弃，只能显式请求。
  final FocusNode _panelFocus = FocusNode(debugLabel: 'desktop select panel');
  final FocusNode _searchFocus = FocusNode(debugLabel: 'desktop select search');
  bool _open = false;
  bool _up = false;
  double _maxHeight = 300;
  double _triggerWidth = 0;

  /// 弹层相对触发器左缘的水平位移（[DesktopSelectAlign] + 视口钳制的结果）。
  double _dx = 0;
  int _active = 0;
  String _query = '';
  OverlayEntry? _entry;

  bool get _searchable => widget.search ?? widget.options.length > 12;

  DesktopSelectOption<T>? get _current {
    for (final option in widget.options) {
      if (option.value == widget.value) {
        return option;
      }
    }
    return null;
  }

  List<DesktopSelectOption<T>> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.options;
    }
    return widget.options
        .where(
          (option) =>
              option.label.toLowerCase().contains(query) ||
              option.value.toString().toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  void dispose() {
    _removeEntry();
    _search.dispose();
    _focus.dispose();
    _panelFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = DesktopSkin.of(context);
    return CompositedTransformTarget(link: _link, child: _trigger(skin));
  }

  Widget _trigger(DesktopSkin skin) {
    final height = switch (widget.variant) {
      DesktopSelectVariant.small => 32.0,
      _ => 36.0,
    };
    final radius = switch (widget.variant) {
      DesktopSelectVariant.pill => DesktopMetrics.radiusCapsule,
      _ => 9.0,
    };
    final focused = _focus.hasFocus || _open;
    final current = _current;
    // 样例 `Select.tsx:68`：触发器是 `aria-haspopup=listbox` + `aria-expanded`。
    // Flutter 侧用 button + expanded 表达，标签由内部文本提供。
    return Semantics(
      button: true,
      expanded: _open,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final key = event.logicalKey;
            // 样例 `Select.tsx:56-62`：收起时 ArrowUp / ArrowDown / Enter /
            // Space 都能打开，不只 ArrowDown。
            if (!_open &&
                (key == LogicalKeyboardKey.arrowDown ||
                    key == LogicalKeyboardKey.arrowUp ||
                    key == LogicalKeyboardKey.enter ||
                    key == LogicalKeyboardKey.numpadEnter ||
                    key == LogicalKeyboardKey.space)) {
              _show();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.escape && _open) {
              _close();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: DesktopHover(
          builder:
              (context, hovered) => GestureDetector(
                onTap: _open ? _close : _show,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: widget.width,
                  height: height,
                  padding: EdgeInsets.only(
                    left: widget.variant == DesktopSelectVariant.pill ? 12 : 10,
                    right: 8,
                  ),
                  decoration: BoxDecoration(
                    color: switch (widget.variant) {
                      DesktopSelectVariant.field => skin.bg,
                      DesktopSelectVariant.small => skin.raise,
                      DesktopSelectVariant.pill =>
                        hovered ? skin.raise2 : skin.raise,
                    },
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow:
                        focused && widget.variant != DesktopSelectVariant.pill
                            ? [
                              BoxShadow(
                                color: skin.accent.withValues(alpha: 0.18),
                                blurRadius: 0,
                                spreadRadius: 4,
                              ),
                            ]
                            : const <BoxShadow>[],
                    border: Border.all(
                      color:
                          // 样例 `.dd-field.bad{border-color:#e57a74}`：错误态压过
                          // 悬停/展开的强调色描边，只让焦点环继续提示位置。
                          widget.invalid
                              ? DesktopPalette.bad
                              : _open
                              ? skin.accent
                              : hovered &&
                                  widget.variant != DesktopSelectVariant.pill
                              ? Color.lerp(skin.line2, skin.accent, 0.4)!
                              : skin.line2,
                    ),
                  ),
                  // 未给 width 时触发器放在 Wrap 里，宽度是无界的：
                  // 这时不能用 Expanded（RenderFlex 会断言 non-zero flex +
                  // unbounded width），改用松约束让文本按内容宽铺开。
                  child: Row(
                    mainAxisSize:
                        widget.width == null
                            ? MainAxisSize.min
                            : MainAxisSize.max,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 15, color: skin.text2),
                        const SizedBox(width: 8),
                      ],
                      if (widget.width == null)
                        Flexible(
                          fit: FlexFit.loose,
                          child: Text(
                            current?.label ?? widget.placeholder ?? '',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.dense(
                              current == null ? skin.text3 : skin.text,
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: Text(
                            current?.label ?? widget.placeholder ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DesktopType.dense(
                              current == null ? skin.text3 : skin.text,
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: DesktopMotion.fast,
                        curve: Curves.easeOut,
                        child: Icon(
                          DesktopIcons.chevDown,
                          size: 14,
                          color: _open ? skin.accent : skin.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ),
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final skin = DesktopSkin.of(context);
    final width = _popWidth(MediaQuery.sizeOf(context).width);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: _up ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: _up ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(_dx, _up ? -6 : 6),
          child: Material(
            type: MaterialType.transparency,
            // 样例 `select.css:11` 的 `.dd-pop`：**不透明** `panel-solid` 底，
            // 投影 `0 28px 64px -18px rgba(0,0,0,.45)` + 1px 内高光线，
            // 入场 `ddin .16s`（下移 4px + scale .98）。
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: MotionToken.reduced(
                context,
                const Duration(milliseconds: 160),
              ),
              curve: Curves.easeOut,
              builder:
                  (context, t, child) => Opacity(
                    opacity: t,
                    alwaysIncludeSemantics: true,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * -4),
                      child: Transform.scale(
                        scale: 0.98 + 0.02 * t,
                        alignment:
                            _up ? Alignment.bottomCenter : Alignment.topCenter,
                        child: child,
                      ),
                    ),
                  ),
              child: Container(
                width: width,
                constraints: BoxConstraints(maxHeight: _maxHeight + 48),
                decoration: BoxDecoration(
                  color: skin.panelSolid,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: skin.line2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(alpha: 0.45),
                      blurRadius: 64,
                      spreadRadius: -18,
                      offset: const Offset(0, 28),
                    ),
                    BoxShadow(
                      color: skin.text.withValues(alpha: 0.04),
                      blurRadius: 0,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _panel(skin),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 弹层宽度：`max(触发器宽, 180)`，pill 档 190，且不超过视口宽度减 16。
  double _popWidth(double screenWidth) {
    final minimum = widget.variant == DesktopSelectVariant.pill ? 190.0 : 180.0;
    final width = _triggerWidth > minimum ? _triggerWidth : minimum;
    return width.clamp(120.0, screenWidth - 16).toDouble();
  }

  Widget _panel(DesktopSkin skin) {
    final items = _filtered;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Focus(
        focusNode: _panelFocus,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowDown) {
            return _move(1, items);
          }
          if (key == LogicalKeyboardKey.arrowUp) {
            return _move(-1, items);
          }
          // 样例 `Select.tsx:56-62`：Home / End 跳到首尾，Tab 收起后继续走焦。
          if (key == LogicalKeyboardKey.home) {
            return _jump(0, items);
          }
          if (key == LogicalKeyboardKey.end) {
            return _jump(items.length - 1, items);
          }
          if (key == LogicalKeyboardKey.tab) {
            _close();
            return KeyEventResult.ignored;
          }
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter) {
            return _choose(items);
          }
          if (key == LogicalKeyboardKey.escape) {
            return _closeAndHandle();
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_searchable)
              // 样例 `select.css:28`：搜索行 42 高、内距 0 14、下沿发丝线，
              // `:focus-within` 时底色 accent 6% + 图标转 accent。
              ListenableBuilder(
                listenable: _searchFocus,
                builder: (context, _) {
                  final focused = _searchFocus.hasFocus;
                  return AnimatedContainer(
                    duration: DesktopMotion.of(context, DesktopMotion.fast),
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color:
                          focused ? skin.accentWash(0.06) : Colors.transparent,
                      border: Border(bottom: BorderSide(color: skin.line2)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          DesktopIcons.search,
                          size: 14,
                          color: focused ? skin.accent : skin.text3,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _search,
                            focusNode: _searchFocus,
                            style: DesktopType.dense(skin.text),
                            cursorColor: skin.accent,
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText:
                                  MaterialLocalizations.of(
                                    context,
                                  ).searchFieldLabel,
                              hintStyle: DesktopType.dense(skin.text3),
                            ),
                            onChanged:
                                (value) => setState(() {
                                  _query = value;
                                  _active = 0;
                                  _entry?.markNeedsBuild();
                                }),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            Flexible(
              child:
                  items.isEmpty
                      ? Padding(
                        // 样例 `select.css:35`：无匹配区 24/10（垂直 24，水平 10）。
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 24,
                        ),
                        child: Text(
                          AppLocalizations.of(context).adminNoMatch,
                          style: DesktopType.caption(skin.text3),
                        ),
                      )
                      : ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: true),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(6),
                          itemCount: items.length,
                          itemBuilder:
                              (context, index) => _option(
                                skin,
                                items[index],
                                active: index == _active,
                              ),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  KeyEventResult _move(int delta, List<DesktopSelectOption<T>> items) {
    if (items.isEmpty) {
      return KeyEventResult.handled;
    }
    setState(() {
      _active = (_active + delta).clamp(0, items.length - 1);
      _entry?.markNeedsBuild();
    });
    return KeyEventResult.handled;
  }

  /// 样例 `Select.tsx:56-62` 的 Home / End：直接跳到首尾。
  KeyEventResult _jump(int index, List<DesktopSelectOption<T>> items) {
    if (items.isEmpty) {
      return KeyEventResult.handled;
    }
    setState(() {
      _active = index.clamp(0, items.length - 1);
      _entry?.markNeedsBuild();
    });
    return KeyEventResult.handled;
  }

  KeyEventResult _choose(List<DesktopSelectOption<T>> items) {
    if (_active < 0 || _active >= items.length) {
      return KeyEventResult.handled;
    }
    _select(items[_active]);
    return KeyEventResult.handled;
  }

  KeyEventResult _closeAndHandle() {
    _close(returnFocus: true);
    return KeyEventResult.handled;
  }

  Widget _option(
    DesktopSkin skin,
    DesktopSelectOption<T> option, {
    required bool active,
  }) {
    final selected = option.value == widget.value;
    // 样例 `Select.tsx:74-77`：每个选项是 `role=option aria-selected`，
    // 且互斥（listbox 的单选语义）。
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: DesktopHover(
        builder:
            (context, hovered) => GestureDetector(
              onTap: () => _select(option),
              behavior: HitTestBehavior.opaque,
              child: Container(
                constraints: const BoxConstraints(minHeight: 34),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color:
                      active || hovered
                          ? selected
                              ? skin.accentWash(0.16)
                              : skin.raise2
                          : selected
                          ? skin.accentWash(0.1)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopType.dense(
                          selected ? skin.accent : skin.text,
                        ).copyWith(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (option.hint != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        option.hint!,
                        maxLines: 1,
                        // 样例 `.dd-opt small`：11.5 / text3 / tabular-nums。
                        style: DesktopType.fieldHint(skin.text3).copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                    if (selected) ...[
                      const SizedBox(width: 8),
                      Icon(DesktopIcons.check, size: 14, color: skin.accent),
                    ],
                  ],
                ),
              ),
            ),
      ),
    );
  }

  void _select(DesktopSelectOption<T> option) {
    _close(returnFocus: true);
    if (option.value != widget.value) {
      widget.onChanged(option.value);
    }
  }

  void _show() {
    if (_open || _entry != null) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || overlayBox == null) {
      return;
    }
    _triggerWidth = box.size.width;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final below = overlayBox.size.height - origin.dy - box.size.height - 12;
    final above = origin.dy - 12;
    // 样例 `Select.tsx:34`：`below < 220 && above > below` 才向上翻转。
    _up = below < 220 && above > below;
    _maxHeight = ((_up ? above : below) - (_searchable ? 48 : 0)).clamp(
      120.0,
      320.0,
    );
    // 样例 `Select.tsx:36`：`align=end` 右缘对齐触发器右缘，左缘对齐左缘，
    // 两者都钳进视口 8px 内。
    final width = _popWidth(overlayBox.size.width);
    final left =
        widget.align == DesktopSelectAlign.end
            ? origin.dx + box.size.width - width
            : origin.dx;
    _dx =
        left.clamp(8.0, overlayBox.size.width - width - 8).toDouble() -
        origin.dx;
    setState(() {
      _open = true;
      _query = '';
      _search.clear();
      _active = widget.options.indexWhere(
        (option) => option.value == widget.value,
      );
      if (_active < 0) {
        _active = 0;
      }
    });
    final entry = OverlayEntry(builder: _overlay);
    _entry = entry;
    overlay.insert(entry);
    // 键盘打开时触发器已经在焦点里，`autofocus` 不会再落地，
    // 这里显式把焦点推进面板（可搜索时直接进搜索框）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_open) {
        return;
      }
      (_searchable ? _searchFocus : _panelFocus).requestFocus();
    });
  }

  /// [returnFocus] 用于键盘收起：把焦点还给触发器，方向键才能重新打开。
  /// Tab 收起必须传 false，否则会把默认走焦拉回原位。
  void _close({bool returnFocus = false}) {
    if (!_open) {
      return;
    }
    setState(() => _open = false);
    _removeEntry();
    if (returnFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focus.requestFocus();
        }
      });
    }
  }

  void _removeEntry() {
    final entry = _entry;
    _entry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }
}
