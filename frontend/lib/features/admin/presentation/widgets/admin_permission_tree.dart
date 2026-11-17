import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';

/// 权限模块编码到本地化名称的映射，未知模块原样返回。
String adminPermissionModuleLabel(AppLocalizations l10n, String module) {
  return switch (module) {
    'activity' => l10n.adminModuleActivity,
    'preference' => l10n.adminModulePreference,
    'profile' => l10n.adminModuleProfile,
    'file' => l10n.adminModuleFile,
    'media' => l10n.adminModuleMedia,
    'photo' => l10n.adminModulePhoto,
    'backdrop' => l10n.adminModuleBackdrop,
    'task' => l10n.adminModuleTask,
    'system' => l10n.adminModuleSystem,
    _ => module,
  };
}

/// 展开收起微过渡时长上限（规范 ≤150ms）。
const Duration _treeMotion = Duration(milliseconds: 150);

/// 树形权限选择器（受控组件）。
///
/// 结构：模块行（展开/收起 chevron + 模块级三态勾选 + 模块名 +
/// 已选 n/总数 mono）→ 子权限行（缩进 + 勾选 + 权限名 + code mono
/// 次级色）。默认全展开，展开收起用 AnimatedRotation/AnimatedSize
/// （≤150ms）微过渡。选择状态由父级持有的扁平 code 集合驱动，
/// 保存语义不变；仅含禁用权限的模块不渲染（沿用旧矩阵口径）。
class AdminPermissionTreePicker extends StatefulWidget {
  const AdminPermissionTreePicker({
    required this.permissions,
    required this.selected,
    required this.onTogglePermission,
    required this.onToggleModule,
    super.key,
  });

  final List<AdminPermissionDetail> permissions;

  /// 已选权限 code 集合（父级唯一事实来源）。
  final Set<String> selected;

  final ValueChanged<AdminPermissionDetail> onTogglePermission;

  /// 模块级勾选：组内存在未勾选项时全选，否则清空该组。
  final ValueChanged<String> onToggleModule;

  @override
  State<AdminPermissionTreePicker> createState() =>
      _AdminPermissionTreePickerState();
}

class _AdminPermissionTreePickerState extends State<AdminPermissionTreePicker> {
  /// 默认全展开。
  late final Set<String> _expanded;

  @override
  void initState() {
    super.initState();
    _expanded =
        widget.permissions
            .where((item) => item.enabled)
            .map((item) => item.module)
            .toSet();
  }

  void _toggleExpanded(String module) {
    setState(() {
      if (!_expanded.remove(module)) {
        _expanded.add(module);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final modules = <String, List<AdminPermissionDetail>>{};
    for (final item in widget.permissions.where((item) => item.enabled)) {
      modules.putIfAbsent(item.module, () => []).add(item);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in modules.entries) ...[
          _ModulePermissionRow(
            module: entry.key,
            permissions: _permissionsOf(entry.key),
            selected: widget.selected,
            expanded: _expanded.contains(entry.key),
            onToggleModule: widget.onToggleModule,
            onToggleExpanded: _toggleExpanded,
          ),
          AnimatedSize(
            duration: _treeMotion,
            alignment: Alignment.topCenter,
            child:
                _expanded.contains(entry.key)
                    ? _buildChildren(context, entry.key)
                    : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  List<AdminPermissionDetail> _permissionsOf(String module) {
    // 组内包含禁用权限（只读展示）；模块分组本身由启用权限派生。
    return widget.permissions
        .where((item) => item.module == module)
        .toList(growable: false);
  }

  Widget _buildChildren(BuildContext context, String module) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final permission in _permissionsOf(module))
          _ChildPermissionRow(
            permission: permission,
            selected: widget.selected.contains(permission.code),
            onToggle: widget.onTogglePermission,
          ),
      ],
    );
  }
}

/// 模块行：chevron + 三态勾选 + 模块名 + 已选 n/总数 mono。
///
/// 整行点按切换展开收起；勾选盒为内层手势，点按不冒泡到行。
class _ModulePermissionRow extends StatelessWidget {
  const _ModulePermissionRow({
    required this.module,
    required this.permissions,
    required this.selected,
    required this.expanded,
    required this.onToggleModule,
    required this.onToggleExpanded,
  });

  final String module;
  final List<AdminPermissionDetail> permissions;
  final Set<String> selected;
  final bool expanded;
  final ValueChanged<String> onToggleModule;
  final ValueChanged<String> onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final enabledCodes = permissions
        .where((item) => item.enabled)
        .map((item) => item.code)
        .toList(growable: false);
    final selectedCount =
        permissions.where((item) => selected.contains(item.code)).length;
    final allSelected =
        enabledCodes.isNotEmpty && enabledCodes.every(selected.contains);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onToggleExpanded(module),
      child: Tooltip(
        message: l10n.adminPermissionToggleModule,
        child: Container(
          key: ValueKey('admin-permission-module-$module'),
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: _treeMotion,
                child: Icon(
                  Icons.keyboard_arrow_right_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              WorkstationCheckMark(
                value: allSelected,
                indeterminate: selectedCount > 0 && !allSelected,
                onChanged: (_) => onToggleModule(module),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  adminPermissionModuleLabel(l10n, module),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$selectedCount/${permissions.length}',
                style: TextStyle(
                  fontFamily: AppTypography.monoFamily,
                  fontFamilyFallback: AppTypography.monoFamilyFallback,
                  fontSize: AppTypography.labelSmall,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 子权限行：缩进 + 勾选 + 权限名 + code mono 次级色。
class _ChildPermissionRow extends StatelessWidget {
  const _ChildPermissionRow({
    required this.permission,
    required this.selected,
    required this.onToggle,
  });

  final AdminPermissionDetail permission;
  final bool selected;
  final ValueChanged<AdminPermissionDetail> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = permission.enabled;
    final nameColor =
        enabled
            ? scheme.onSurface
            : scheme.onSurfaceVariant.withValues(alpha: 0.45);
    return Container(
      key: ValueKey('admin-permission-row-${permission.code}'),
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.only(left: 34, top: 2, bottom: 2),
      child: Row(
        children: [
          WorkstationCheckMark(
            value: selected,
            enabled: enabled,
            onChanged: enabled ? (_) => onToggle(permission) : null,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              permission.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: nameColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            permission.code,
            style: TextStyle(
              fontFamily: AppTypography.monoFamily,
              fontFamilyFallback: AppTypography.monoFamilyFallback,
              fontSize: AppTypography.labelSmall,
              color: scheme.onSurfaceVariant.withValues(
                alpha: enabled ? 1 : 0.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
