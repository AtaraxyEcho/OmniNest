import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/files/application/share_link_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/files/presentation/widgets/files_dialog.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';

/// 密码模式。
enum _PasswordMode { custom, random }

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
      backgroundColor: Colors.transparent,
      builder: (_) => ShareLinkSheet(file: file, existingShare: existingShare),
    );
  }

  @override
  ConsumerState<ShareLinkSheet> createState() => _ShareLinkSheetState();
}

class _ShareLinkSheetState extends ConsumerState<ShareLinkSheet> {
  final _maxAccessController = TextEditingController();
  final _passwordController = TextEditingController();
  DateTime? _expiresAt;
  bool _showOptions = false;
  bool _enablePassword = false;
  _PasswordMode _passwordMode = _PasswordMode.random;

  /// 分享基址（服务器下发优先）；打开面板时解析一次。
  String? _shareBaseUrl;

  @override
  void initState() {
    super.initState();
    unawaited(_resolveShareBaseUrl());
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

    return Material(
      color: context.filesColors.surfaceContainer,
      child: Container(
        decoration: BoxDecoration(
          // 桌面嵌入弹窗形态由外层弹窗壳描边，内层再加边框会形成双线；
          // 仅贴底抽屉形态保留顶部分隔线。
          border:
              widget.embedded
                  ? null
                  : Border(
                    top: BorderSide(color: context.filesColors.outlineVariant),
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
              ] else ...[
                _buildCreateSection(shareState),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.zero,
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

  Widget _buildCreateSection(AsyncValue<FileShareLink?> shareState) {
    final l10n = AppLocalizations.of(context);
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
            '${l10n.filesCreateFailed}：${shareState.error}',
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

  Widget _buildShareInfo(FileShareLink share) {
    final l10n = AppLocalizations.of(context);
    // 基址解析完成前先占位（复制按钮同时禁用）。
    final baseUrl = _shareBaseUrl;
    final shareUrl = baseUrl == null ? null : '$baseUrl/#/s/${share.shareCode}';
    final hasPassword = share.generatedPassword != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shareUrl ?? '…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.bodySmall,
                        fontFamily: AppTypography.monoFamily,
                        fontFamilyFallback: AppTypography.monoFamilyFallback,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap:
                        shareUrl == null
                            ? null
                            : () => _copyToClipboard(shareUrl),
                    borderRadius: BorderRadius.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy,
                        size: 16,
                        color: context.filesColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasPassword) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.key,
                      size: 13,
                      color: context.filesColors.onSurface,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.filesSharePasswordLabel(share.generatedPassword!),
                      style: TextStyle(
                        fontSize: AppTypography.bodySmall,
                        fontFamily: AppTypography.monoFamily,
                        fontFamilyFallback: AppTypography.monoFamilyFallback,
                        fontWeight: FontWeight.w600,
                        color: context.filesColors.onSurface,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => _copyToClipboard(share.generatedPassword!),
                      borderRadius: BorderRadius.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          Icons.copy,
                          size: 13,
                          color: context.filesColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  _buildStatusChip(
                    _statusText(share.status),
                    isActive: share.status.toUpperCase() == 'ACTIVE',
                  ),
                  if (share.maxAccessCount != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${share.accessCount}/${share.maxAccessCount}',
                      style: TextStyle(
                        fontSize: AppTypography.labelSmall,
                        color: context.filesColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (share.expiresAt != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.schedule,
                      size: 12,
                      color: context.filesColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      _formatCompactDate(share.expiresAt!),
                      style: TextStyle(
                        fontSize: AppTypography.labelSmall,
                        color: context.filesColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        // 纯复制链接与链接行右侧复制 icon 完全重复，已删；
        // 仅保留“含密码复制”（组合了提取码，功能独立）。
        if (hasPassword && shareUrl != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildCapsuleButton(
                l10n.filesCopyLinkWithPassword,
                Icons.copy,
                () => _copyToClipboard(shareUrl),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStatusChip(String label, {required bool isActive}) {
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
          expiresAt: _expiresAt,
          maxAccessCount: maxAccess,
        );
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
      duration: const Duration(seconds: 1),
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
