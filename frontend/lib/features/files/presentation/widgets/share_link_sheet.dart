import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/files/application/share_link_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/mobile_status_kit.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/files/presentation/widgets/files_dialog.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/core/widgets/mobile_sheet_semantics.dart';

part 'share_link_sheet_mobile.dart';
part 'share_link_sheet_sections.dart';

/// 口令模式。
enum _PasswordMode { custom, random }

/// 分享有效期预设（原型 `.segmented`：Permanent / 7 days / 30 days）。
enum _ShareExpiryPreset {
  permanent(0),
  days7(7),
  days30(30);

  const _ShareExpiryPreset(this.days);

  /// 距现在的天数；0 表示永久有效。
  final int days;
}

/// 分享链接创建/查看底部弹窗。
class ShareLinkSheet extends ConsumerStatefulWidget {
  const ShareLinkSheet({
    required this.file,
    this.existingShare,
    this.embedded = false,
    super.key,
  });

  final FileNode file;
  final FileShareLink? existingShare;

  /// true 时作为直角弹窗 Body 嵌入（桌面端），不再渲染抽屉把手与圆角。
  final bool embedded;

  static Future<void> show(
    BuildContext context, {
    required FileNode file,
    FileShareLink? existingShare,
  }) {
    final l10n = AppLocalizations.of(context);
    // 弹窗可能被遮罩、下滑或外层关闭键关闭；统一在打开时清空上一份分享状态，
    // 避免快速切换文件时短暂显示上一个文件的链接。
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(shareLinkControllerProvider.notifier).reset();
    // 面板经根导航器呈现，默认拿不到壳层暗皮肤与 Files 环境重绑；
    // 在调用点捕获宿主环境，面板子树内重放。
    final ambience = MobileSheetAmbience.capture(context);
    final desktop =
        MediaQuery.sizeOf(context).width >= 600 &&
        !MobileShellScope.isHosted(context);
    if (desktop) {
      return showFilesDialog<void>(
        context: context,
        builder:
            (_) => FilesDialogFrame(
              title: l10n.filesShare,
              headerLabel: file.isFolder ? 'FOLDER' : file.nodeType,
              width: 520,
              body: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ShareLinkSheet(
                  file: file,
                  existingShare: existingShare,
                  embedded: true,
                ),
              ),
            ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // 移动壳层：原型 `.glass-sheet` 形态（实底 #171E1C + 顶部 r28）。
      backgroundColor:
          ambience.hosted ? context.env.sheetSolid : Colors.transparent,
      shape:
          ambience.hosted
              ? const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              )
              : null,
      builder:
          (_) => MobileSheetSemantics(
            child: ambience.wrap(
              ShareLinkSheet(file: file, existingShare: existingShare),
            ),
          ),
    );
  }

  @override
  ConsumerState<ShareLinkSheet> createState() => _ShareLinkSheetState();
}

class _ShareLinkSheetState extends ConsumerState<ShareLinkSheet> {
  final _maxAccessController = TextEditingController();
  final _passwordController = TextEditingController();
  DateTime? _expiresAt;
  _ShareExpiryPreset? _expiryPreset;
  bool _showOptions = false;
  bool _enablePassword = false;
  _PasswordMode _passwordMode = _PasswordMode.random;

  /// 分享基址（服务器下发优先）；打开面板时解析一次。
  String? _shareBaseUrl;

  /// 编辑态：勾选后才对已建分享下发"清除密码"，不勾选且密码框为空即保持原值。
  bool _clearPasswordRequested = false;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveShareBaseUrl());
    final existing = widget.existingShare;
    if (existing != null) {
      // 编辑表单以分享当前设置起算，未改动的那一项保存时必须写回原值而不是清空。
      _expiresAt = existing.expiresAt;
      if (existing.maxAccessCount != null) {
        _maxAccessController.text = '${existing.maxAccessCount}';
      }
    }
  }

  /// 跨 part 文件的状态更新入口：扩展成员不算 State 实例成员，不能直接调 setState。
  void _updateState(VoidCallback update) {
    if (mounted) {
      setState(update);
    }
  }

  Future<void> _resolveShareBaseUrl() async {
    try {
      final baseUrl = await ref.read(webShareBaseUrlResolverProvider).resolve();
      if (mounted) {
        setState(() => _shareBaseUrl = baseUrl);
      }
    } on Object {
      // 环境未配置（StateError 属 Error 而非 Exception，on Exception
      // 接不住）与读取失败都由分享创建流程暴露，这里保持占位。
    }
  }

  @override
  void dispose() {
    _maxAccessController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shareState = ref.watch(shareLinkControllerProvider);
    final existing =
        widget.existingShare ?? (shareState.hasValue ? shareState.value : null);
    final hosted = !widget.embedded && MobileShellScope.isHosted(context);

    return Material(
      // 托管贴底面板由 sheet 路由绘制实底圆角表面，内层保持透明避免
      // 再叠一层半透明玻璃底。
      color: hosted ? Colors.transparent : context.filesColors.surfaceContainer,
      child: Container(
        decoration: BoxDecoration(
          // 桌面嵌入弹窗形态由外层弹窗壳描边，内层再加边框会形成双线；
          // 仅贴底抽屉形态保留顶部分隔线。
          border:
              widget.embedded
                  ? null
                  : Border(
                    top: BorderSide(
                      color:
                          hosted
                              ? context.env.line13
                              : context.filesColors.outlineVariant,
                    ),
                  ),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.embedded) ...[
                _buildHandle(),
                const SizedBox(height: 14),
              ],
              _buildHeader(),
              const SizedBox(height: 16),
              if (existing != null) ...[
                _buildShareInfo(existing),
                // 已建分享必须能改设置：否则改一次有效期只能撤销重发，
                // 已经发出去的地址会直接失效。
                _buildEditSection(existing, shareState),
              ] else ...[
                _buildCreateSection(shareState, hosted: hosted),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    // 原型 `.sheet-handle`：36×4 r3 白 22%；工位形态沿用主题描边色。
    final hosted = MobileShellScope.isHosted(context);
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color:
              hosted
                  ? context.env.line25
                  : Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(hosted ? 3 : 0),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(
          widget.file.isFolder
              ? Icons.folder_rounded
              : Icons.insert_drive_file_outlined,
          color: context.filesColors.primary,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            widget.file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppTypography.titleMedium,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // 弹窗嵌入形态由弹窗壳统一提供 X；贴底抽屉保留自带关闭钮。
        if (!widget.embedded)
          IconButton(
            tooltip: AppLocalizations.of(context).coreClose,
            icon: const Icon(Icons.close, size: 20),
            onPressed: () {
              ref.read(shareLinkControllerProvider.notifier).reset();
              Navigator.of(context).pop();
            },
          ),
      ],
    );
  }

  Widget _buildCreateSection(
    AsyncValue<FileShareLink?> shareState, {
    required bool hosted,
  }) {
    final l10n = AppLocalizations.of(context);
    final errorMessage =
        shareState.hasError
            ? userFacingErrorText(shareState.error!, l10n: l10n)
            : null;
    if (hosted) {
      return _HostedCreateSection(
        enablePassword: _enablePassword,
        onPasswordChanged: (value) => setState(() => _enablePassword = value),
        passwordMode: _passwordMode,
        onPasswordModeChanged: (mode) => setState(() => _passwordMode = mode),
        passwordController: _passwordController,
        expiryPreset: _hostedExpiryPreset,
        onExpiryPresetChanged:
            (preset) => setState(() {
              _expiryPreset = preset;
              _expiresAt = null;
            }),
        optionsExpanded: _showOptions,
        onToggleOptions: () => setState(() => _showOptions = !_showOptions),
        maxAccessController: _maxAccessController,
        busy: shareState.isLoading,
        onSubmit: _createShareLink,
        errorMessage: errorMessage,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPasswordSection(),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() => _showOptions = !_showOptions),
          child: Row(
            children: [
              Icon(
                _showOptions ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: context.filesColors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                l10n.filesAdvancedOptions,
                style: TextStyle(
                  fontSize: AppTypography.bodyMedium,
                  color: context.filesColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_showOptions) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _maxAccessController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.filesMaxAccessCount,
              hintText: l10n.filesNoLimit,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.filesExpiryTime),
            subtitle: Text(
              _expiresAt != null
                  ? _formatDateTime(_expiresAt!)
                  : l10n.filesNeverExpire,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_expiresAt != null)
                  IconButton(
                    tooltip: AppLocalizations.of(context).coreClear,
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => setState(() => _expiresAt = null),
                  ),
                IconButton(
                  tooltip: AppLocalizations.of(context).coreChooseDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  onPressed: _pickExpiryDate,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: shareState.isLoading ? null : _createShareLink,
            icon:
                shareState.isLoading
                    ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.link),
            label: Text(l10n.filesCreateShareLink),
          ),
        ),
        if (shareState.hasError) ...[
          const SizedBox(height: 8),
          Text(
            '${l10n.filesCreateFailed}：$errorMessage',
            style: TextStyle(
              color: context.filesColors.error,
              fontSize: AppTypography.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPasswordSection() {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 方形开关行：与工位弹窗框架同一设计语言（M3 胶囊开关
        // 无法经主题直角化，见 workstation_skin switchTheme 注释）。
        WorkstationToggle(
          value: _enablePassword,
          onChanged: (v) => setState(() => _enablePassword = v),
          label: l10n.filesSetPassword,
          subtitle:
              _enablePassword
                  ? l10n.filesPasswordRequired
                  : l10n.filesNoPasswordAnyone,
        ),
        if (_enablePassword) ...[
          const SizedBox(height: 8),
          // SegmentedButton 高度只有 40/32 两档可达（minimumSize 在段内
          // 不生效），取 compact 32 后在 36/44 输入框槽位内垂直居中，
          // 保证控件节奏与相邻字段一致。
          SizedBox(
            height: AppControlTokens.fieldHeight,
            child: Center(
              child: SegmentedButton<_PasswordMode>(
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                segments: [
                  ButtonSegment(
                    value: _PasswordMode.random,
                    label: Text(l10n.filesRandomGenerate),
                  ),
                  ButtonSegment(
                    value: _PasswordMode.custom,
                    label: Text(l10n.filesCustomPassword),
                  ),
                ],
                selected: {_passwordMode},
                onSelectionChanged:
                    (v) => setState(() => _passwordMode = v.first),
              ),
            ),
          ),
          if (_passwordMode == _PasswordMode.custom) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.filesCustomPassword,
                hintText: l10n.filesEnterPassword,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _saveShareSettings(FileShareLink share) async {
    final l10n = AppLocalizations.of(context);
    final maxText = _maxAccessController.text.trim();
    final maxAccess = int.tryParse(maxText);
    if (maxText.isNotEmpty && (maxAccess == null || maxAccess < 0)) {
      showOmniFeedback(context, l10n.filesMaxAccessCount);
      return;
    }
    final typedPassword = _passwordController.text.trim();
    final updated = await ref
        .read(shareLinkControllerProvider.notifier)
        .updateShareLink(
          shareId: share.id,
          // 三种意图必须分开：勾清除才下发空串，填了新值才下发替换，
          // 其余情况传 null 保持原密码（服务端把 null 当作"不改"）。
          password:
              _clearPasswordRequested
                  ? ''
                  : (typedPassword.isEmpty ? null : typedPassword),
          // 有效期与次数上限按界面实况整条下发：起算值已在 initState 预填。
          expiresAt:
              _expiresAt == null ? '' : _expiresAt!.toUtc().toIso8601String(),
          maxAccessCount: maxAccess ?? 0,
        );
    if (!mounted) {
      return;
    }
    if (updated != null) {
      setState(() {
        _clearPasswordRequested = false;
        _passwordController.clear();
      });
      showOmniFeedback(context, l10n.filesShareSettingsSaved);
    }
  }

  Widget _buildStatusChip(
    String label, {
    required bool isActive,
    bool hosted = false,
  }) {
    // 移动壳层用原型状态丸（7px 大写 + 色调底），工位保留直角小胶囊。
    if (hosted) {
      return MobileStatusPill(
        label: label,
        tone: isActive ? MobileStatusTone.calm : MobileStatusTone.danger,
      );
    }
    final color =
        isActive ? context.filesColors.primary : context.filesColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.zero,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTypography.labelSmall,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCapsuleButton(String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        style: const TextStyle(fontSize: AppTypography.bodyMedium),
      ),
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Future<void> _createShareLink() async {
    final l10n = AppLocalizations.of(context);
    final maxAccess =
        _maxAccessController.text.isNotEmpty
            ? int.tryParse(_maxAccessController.text)
            : null;

    String? password;
    bool generatePassword = false;
    if (_enablePassword) {
      if (_passwordMode == _PasswordMode.custom) {
        password = _passwordController.text.trim();
        if (password.isEmpty) {
          showOmniFeedback(context, l10n.filesEnterCustomPassword);
          return;
        }
      } else {
        generatePassword = true;
      }
    }

    await ref
        .read(shareLinkControllerProvider.notifier)
        .createShareLink(
          resourceId: widget.file.id,
          resourceType: widget.file.isFolder ? 'FOLDER' : 'FILE',
          password: password,
          generatePassword: generatePassword,
          expiresAt: _resolvedExpiresAt(),
          maxAccessCount: maxAccess,
        );
  }

  /// 有效期取值：移动托管态由预设分段决定，桌面态沿用日期选择器。
  DateTime? _resolvedExpiresAt() {
    final preset = _expiryPreset;
    if (preset == null) {
      return _expiresAt;
    }
    return preset.days == 0
        ? null
        : DateTime.now().add(Duration(days: preset.days));
  }

  /// 分段选中档：未显式选择时按已设置的到期时间回推。
  _ShareExpiryPreset get _hostedExpiryPreset {
    final preset = _expiryPreset;
    if (preset != null) {
      return preset;
    }
    final expiresAt = _expiresAt;
    if (expiresAt == null) {
      return _ShareExpiryPreset.permanent;
    }
    return expiresAt.difference(DateTime.now()).inDays >= 21
        ? _ShareExpiryPreset.days30
        : _ShareExpiryPreset.days7;
  }

  Future<void> _copyToClipboard(String text) async {
    final l10n = AppLocalizations.of(context);
    final copied = await copyTextToClipboard(text);
    if (!mounted) {
      return;
    }
    showOmniFeedback(
      context,
      copied ? l10n.filesCopiedClipboard : l10n.clipboardCopyFailed,
      severity:
          copied ? OmniFeedbackSeverity.success : OmniFeedbackSeverity.error,
    );
  }

  Future<void> _pickExpiryDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null && mounted) {
        setState(() {
          _expiresAt = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  String _statusText(String status) {
    final l10n = AppLocalizations.of(context);
    return switch (status.toUpperCase()) {
      'ACTIVE' => l10n.filesShareActive,
      'REVOKED' => l10n.filesShareRevoked,
      'EXPIRED' => l10n.filesShareExpired,
      'EXHAUSTED' => l10n.filesShareExhausted,
      _ => status,
    };
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatCompactDate(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
