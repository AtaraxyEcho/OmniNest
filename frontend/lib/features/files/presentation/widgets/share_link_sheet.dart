import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/files/application/share_link_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';

/// 密码模式。
enum _PasswordMode { custom, random }

/// 分享链接创建/查看底部弹窗。
class ShareLinkSheet extends ConsumerStatefulWidget {
  const ShareLinkSheet({required this.file, this.existingShare, super.key});

  final FileNode file;
  final FileShareLink? existingShare;

  static Future<void> show(
    BuildContext context, {
    required FileNode file,
    FileShareLink? existingShare,
  }) {
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

    return Container(
      decoration: BoxDecoration(
        color: context.filesColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHandle(),
            const SizedBox(height: 16),
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
          borderRadius: BorderRadius.circular(2),
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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l10n.filesSetPassword),
          subtitle: Text(
            _enablePassword
                ? l10n.filesPasswordRequired
                : l10n.filesNoPasswordAnyone,
            style: TextStyle(
              fontSize: AppTypography.bodySmall,
              color: context.filesColors.onSurfaceVariant,
            ),
          ),
          value: _enablePassword,
          onChanged: (v) => setState(() => _enablePassword = v),
        ),
        if (_enablePassword) ...[
          const SizedBox(height: 8),
          SegmentedButton<_PasswordMode>(
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
            onSelectionChanged: (v) => setState(() => _passwordMode = v.first),
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
    final baseUrl = ref.read(appEnvironmentProvider).effectiveWebBaseUrl;
    final shareUrl = '$baseUrl/#/s/${share.shareCode}';
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
            borderRadius: BorderRadius.circular(10),
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
                      shareUrl,
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
                    onTap: () => _copyToClipboard(shareUrl),
                    borderRadius: BorderRadius.circular(6),
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
                      borderRadius: BorderRadius.circular(4),
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
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (hasPassword)
              _buildCapsuleButton(
                l10n.filesCopyLinkWithPassword,
                Icons.copy,
                () => _copyToClipboard(shareUrl),
              ),
            _buildCapsuleButton(
              hasPassword ? l10n.filesCopyLinkOnly : l10n.filesCopyLink,
              Icons.link,
              () => _copyToClipboard(shareUrl),
            ),
          ],
        ),
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
        borderRadius: BorderRadius.circular(4),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.filesEnterCustomPassword)),
          );
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
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.filesCopiedClipboard),
          duration: const Duration(seconds: 1),
        ),
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
