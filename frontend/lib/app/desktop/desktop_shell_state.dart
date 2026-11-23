import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:omninest/app/theme/desktop/desktop_palette.dart';

/// 桌面壳层的外观偏好（样例 Settings → Appearance / Atmosphere）。
@immutable
class DesktopAppearance {
  const DesktopAppearance({
    this.accent = DesktopAccent.sage,
    this.ambient = 70,
    this.reduceMotion = false,
    this.compact = false,
    this.dynamicBg = true,
  });

  final DesktopAccent accent;

  /// 环境光强度 0-100，对应样例 `--amb-op` 前的 opacity 系数。
  final double ambient;
  final bool reduceMotion;
  final bool compact;

  /// 随封面变色的动态背景开关（关闭时全站切至纯净 Plain 背景）。
  final bool dynamicBg;

  DesktopAppearance copyWith({
    DesktopAccent? accent,
    double? ambient,
    bool? reduceMotion,
    bool? compact,
    bool? dynamicBg,
  }) {
    return DesktopAppearance(
      accent: accent ?? this.accent,
      ambient: ambient ?? this.ambient,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      compact: compact ?? this.compact,
      dynamicBg: dynamicBg ?? this.dynamicBg,
    );
  }
}

final desktopAppearanceProvider =
    NotifierProvider<DesktopAppearanceController, DesktopAppearance>(
      DesktopAppearanceController.new,
    );

/// 设备本地偏好：强调色与环境光是「这台机器的观感」，不随账号漫游，
/// 因此只落 SharedPreferences，不进偏好同步服务。
class DesktopAppearanceController extends Notifier<DesktopAppearance> {
  static const _accentKey = 'omninest.desktop.accent';
  static const _ambientKey = 'omninest.desktop.ambient';
  static const _reduceKey = 'omninest.desktop.reduceMotion';
  static const _compactKey = 'omninest.desktop.compact';
  static const _dynamicBgKey = 'omninest.desktop.dynamicBg';

  bool _loaded = false;

  @override
  DesktopAppearance build() => const DesktopAppearance();

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    state = DesktopAppearance(
      accent: DesktopAccent.fromName(prefs.getString(_accentKey)),
      ambient: (prefs.getDouble(_ambientKey) ?? 70).clamp(0, 100),
      reduceMotion: prefs.getBool(_reduceKey) ?? false,
      compact: prefs.getBool(_compactKey) ?? false,
      dynamicBg: prefs.getBool(_dynamicBgKey) ?? true,
    );
  }

  Future<void> setAccent(DesktopAccent accent) async {
    state = state.copyWith(accent: accent);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accentKey, accent.name);
  }

  Future<void> setAmbient(double value) async {
    state = state.copyWith(ambient: value.clamp(0, 100));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_ambientKey, state.ambient);
  }

  Future<void> setReduceMotion(bool value) async {
    state = state.copyWith(reduceMotion: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reduceKey, value);
  }

  Future<void> setCompact(bool value) async {
    state = state.copyWith(compact: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_compactKey, value);
  }

  Future<void> setDynamicBg(bool value) async {
    state = state.copyWith(dynamicBg: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dynamicBgKey, value);
  }
}

/// 顶栏前进/后退的历史栈。
///
/// go_router 只暴露 pop，没有「前进」；样例的顶栏两个方向都要能用，
/// 因此壳层自己记一条路径栈：外部导航追加，按钮导航只移动游标，
/// 用 [_programmatic] 抑制回写，避免 go 触发的路由回调再追加一次。
@immutable
class DesktopHistory {
  const DesktopHistory({this.entries = const <String>[], this.cursor = -1});

  final List<String> entries;
  final int cursor;

  bool get canGoBack => cursor > 0;
  bool get canGoForward => cursor >= 0 && cursor < entries.length - 1;
}

final desktopHistoryProvider =
    NotifierProvider<DesktopHistoryController, DesktopHistory>(
      DesktopHistoryController.new,
    );

class DesktopHistoryController extends Notifier<DesktopHistory> {
  bool _programmatic = false;

  @override
  DesktopHistory build() => const DesktopHistory();

  void record(String path) {
    if (_programmatic) {
      _programmatic = false;
      return;
    }
    final current = state;
    if (current.cursor >= 0 && current.entries[current.cursor] == path) {
      return;
    }
    final kept = current.entries.take(current.cursor + 1).toList()..add(path);
    state = DesktopHistory(entries: kept, cursor: kept.length - 1);
  }

  String? back() {
    if (!state.canGoBack) {
      return null;
    }
    final next = state.cursor - 1;
    _programmatic = true;
    state = DesktopHistory(entries: state.entries, cursor: next);
    return state.entries[next];
  }

  String? forward() {
    if (!state.canGoForward) {
      return null;
    }
    final next = state.cursor + 1;
    _programmatic = true;
    state = DesktopHistory(entries: state.entries, cursor: next);
    return state.entries[next];
  }
}

/// 详情坞的动作：由推入详情的模块提供，坞负责渲染并传入当前活跃的 context 与 ref。
@immutable
class DesktopDetailAction {
  const DesktopDetailAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final void Function(BuildContext context, WidgetRef ref) onPressed;
}

/// 详情坞的内容契约。
///
/// 坞不认识影视/音乐/图书/文件的领域类型：模块把自己的对象翻译成这份
/// 视图模型再推入，壳层因此不需要跨模块 import，也不会随领域模型演进碎裂。
@immutable
class DesktopDetailData {
  const DesktopDetailData({
    required this.kind,
    required this.title,
    this.id,
    this.subtitle,
    this.imageUrl,
    this.badge,
    this.about,
    this.facts = const <MapEntry<String, String>>[],
    this.factsLabel,
    this.chips = const <String>[],
    this.chipsLabel,
    this.progress,
    this.primary,
    this.secondary,
    this.squareArt = false,
    this.paperCover,
  });

  final String kind;
  final String title;
  final String? id;
  final String? subtitle;
  final String? imageUrl;
  final String? badge;
  final String? about;
  final List<MapEntry<String, String>> facts;
  final String? factsLabel;
  final List<String> chips;
  final String? chipsLabel;
  final double? progress;
  final DesktopDetailAction? primary;
  final DesktopDetailAction? secondary;

  /// 方形封面（音轨/图书）与 16:10 横图（影视）的分叉。
  final bool squareArt;

  /// 无封面图书的纸封底色与文字色。
  final ({Color tone, Color ink})? paperCover;

  String get effectiveId => id ?? '$kind:$title';
}

/// 右键菜单项。
@immutable
class DesktopMenuItem {
  const DesktopMenuItem({
    this.label,
    this.icon,
    this.shortcut,
    this.onPressed,
    this.danger = false,
    this.disabled = false,
    this.separator = false,
  });

  const DesktopMenuItem.separator()
    : label = null,
      icon = null,
      shortcut = null,
      onPressed = null,
      danger = false,
      disabled = false,
      separator = true;

  final String? label;
  final IconData? icon;
  final String? shortcut;
  final VoidCallback? onPressed;
  final bool danger;
  final bool disabled;
  final bool separator;
}

@immutable
class DesktopMenuRequest {
  const DesktopMenuRequest({required this.position, required this.items});

  final Offset position;
  final List<DesktopMenuItem> items;
}

enum DesktopDockTab { details, queue }

/// 顶栏浮层的互斥槽位：样例里三个面板任意时刻只开一个。
enum DesktopPanel { none, account, notifications, tasks }

@immutable
class DesktopShellState {
  const DesktopShellState({
    this.sidebarExpanded = true,
    this.dockOpen = false,
    this.dockTab = DesktopDockTab.details,
    this.detail,
    this.panel = DesktopPanel.none,
    this.commandPaletteOpen = false,
    this.shortcutsOpen = false,
    this.menu,
  });

  final bool sidebarExpanded;
  final bool dockOpen;
  final DesktopDockTab dockTab;
  final DesktopDetailData? detail;
  final DesktopPanel panel;
  final bool commandPaletteOpen;
  final bool shortcutsOpen;
  final DesktopMenuRequest? menu;

  DesktopShellState copyWith({
    bool? sidebarExpanded,
    bool? dockOpen,
    DesktopDockTab? dockTab,
    Object? detail = _sentinel,
    DesktopPanel? panel,
    bool? commandPaletteOpen,
    bool? shortcutsOpen,
    Object? menu = _sentinel,
  }) {
    return DesktopShellState(
      sidebarExpanded: sidebarExpanded ?? this.sidebarExpanded,
      dockOpen: dockOpen ?? this.dockOpen,
      dockTab: dockTab ?? this.dockTab,
      detail:
          identical(detail, _sentinel)
              ? this.detail
              : detail as DesktopDetailData?,
      panel: panel ?? this.panel,
      commandPaletteOpen: commandPaletteOpen ?? this.commandPaletteOpen,
      shortcutsOpen: shortcutsOpen ?? this.shortcutsOpen,
      menu:
          identical(menu, _sentinel) ? this.menu : menu as DesktopMenuRequest?,
    );
  }

  static const Object _sentinel = Object();
}

final desktopShellProvider =
    NotifierProvider<DesktopShellController, DesktopShellState>(
      DesktopShellController.new,
    );

class DesktopShellController extends Notifier<DesktopShellState> {
  @override
  DesktopShellState build() => const DesktopShellState();

  void toggleSidebar() =>
      state = state.copyWith(sidebarExpanded: !state.sidebarExpanded);

  void toggleDock() =>
      state = state.copyWith(
        dockOpen: !state.dockOpen,
        panel: DesktopPanel.none,
      );

  void setDock(bool open) => state = state.copyWith(dockOpen: open);

  void setDockTab(DesktopDockTab tab) =>
      state = state.copyWith(dockTab: tab, dockOpen: true);

  void showDetail(DesktopDetailData detail) =>
      state = state.copyWith(
        detail: detail,
        dockOpen: true,
        dockTab: DesktopDockTab.details,
        panel: DesktopPanel.none,
      );

  /// 仅更新当前详情数据，不强弹 Dock；当 Dock 已展开时可实时联动刷新。
  void selectDetail(DesktopDetailData? detail) =>
      state = state.copyWith(detail: detail);

  /// 清空当前详情数据（切主路由时调用，防止跨模块残留）。
  void clearDetail() => state = state.copyWith(detail: null);

  void togglePanel(DesktopPanel panel) =>
      state = state.copyWith(
        panel: state.panel == panel ? DesktopPanel.none : panel,
      );

  void setPanel(DesktopPanel panel) => state = state.copyWith(panel: panel);

  void toggleCommandPalette() =>
      state = state.copyWith(
        commandPaletteOpen: !state.commandPaletteOpen,
        panel: DesktopPanel.none,
        menu: null,
      );

  void setCommandPalette(bool open) =>
      state = state.copyWith(commandPaletteOpen: open);

  void setShortcuts(bool open) => state = state.copyWith(shortcutsOpen: open);

  void openMenu(Offset position, List<DesktopMenuItem> items) =>
      state = state.copyWith(
        menu: DesktopMenuRequest(position: position, items: items),
        panel: DesktopPanel.none,
      );

  void closeMenu() => state = state.copyWith(menu: null);

  /// Esc 的逐层收束：菜单 → 命令面板 → 快捷键 → 顶栏浮层 → 详情坞。
  bool dismissTopLayer() {
    if (state.menu != null) {
      closeMenu();
      return true;
    }
    if (state.commandPaletteOpen) {
      setCommandPalette(false);
      return true;
    }
    if (state.shortcutsOpen) {
      setShortcuts(false);
      return true;
    }
    if (state.panel != DesktopPanel.none) {
      setPanel(DesktopPanel.none);
      return true;
    }
    if (state.dockOpen) {
      setDock(false);
      return true;
    }
    return false;
  }
}
