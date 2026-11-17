import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/files_colors.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';

Map<String, String> _providerLabels(AppLocalizations l10n) => {
  'S3': l10n.filesS3Compatible,
  'WEBDAV': 'WebDAV',
  'ONEDRIVE': 'OneDrive',
  'GDRIVE': 'Google Drive',
  'DROPBOX': 'Dropbox',
};

const List<String> _s3ProviderTypes = [
  'AWS',
  'Minio',
  'Alibaba',
  'TencentCOS',
  'HuaweiOBS',
];

const List<String> _webdavVendors = [
  'other',
  'nextcloud',
  'owncloud',
  'sharepoint',
  'fastmail',
  'yandex',
];

/// 创建或编辑外部存储账号的凭据表单。
class ExternalStorageAccountDialog extends StatefulWidget {
  const ExternalStorageAccountDialog({
    this.account,
    this.connectors = const [],
    super.key,
  });

  /// 非空时表示编辑模式，预填表单且禁用 provider 切换。
  final ExternalStorageAccount? account;

  /// 服务端连接器目录；为空时回退到内置允许列表。
  final List<ExternalStorageConnector> connectors;

  @override
  State<ExternalStorageAccountDialog> createState() =>
      _ExternalStorageAccountDialogState();
}

class _ExternalStorageAccountDialogState
    extends State<ExternalStorageAccountDialog> {
  String _provider = 'S3';
  String _s3ProviderType = 'Minio';
  String _webdavVendor = 'other';

  late final TextEditingController _displayNameCtrl;
  // S3 凭据
  late final TextEditingController _s3AccessKeyCtrl;
  late final TextEditingController _s3SecretKeyCtrl;
  late final TextEditingController _s3EndpointCtrl;
  late final TextEditingController _s3RegionCtrl;
  // WebDAV 凭据
  late final TextEditingController _webdavUrlCtrl;
  late final TextEditingController _webdavUserCtrl;
  late final TextEditingController _webdavPassCtrl;

  bool get _isOAuthProvider {
    final code = _provider.toUpperCase();
    return code == 'ONEDRIVE' ||
        code == 'GDRIVE' ||
        code == 'GOOGLE_DRIVE' ||
        code == 'DROPBOX';
  }

  /// OAuth 连接器依赖实例级应用：目录明确报告未配置时禁止提交，
  /// 服务端创建接口以同样规则兜底。目录不可用时放行，由服务端拒绝并提示。
  bool get _oauthAppMissing {
    if (!_isOAuthProvider) {
      return false;
    }
    final connector = widget.connectors.where(
      (item) => item.code.toUpperCase() == _provider.toUpperCase(),
    );
    return connector.isNotEmpty && !connector.first.oauthConfigured;
  }

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _displayNameCtrl = TextEditingController(text: account?.displayName ?? '');
    _s3AccessKeyCtrl = TextEditingController();
    _s3SecretKeyCtrl = TextEditingController();
    _s3EndpointCtrl = TextEditingController();
    _s3RegionCtrl = TextEditingController();
    _webdavUrlCtrl = TextEditingController();
    _webdavUserCtrl = TextEditingController();
    _webdavPassCtrl = TextEditingController();

    if (account != null) {
      _provider = account.provider;
      _prefillCredentials(account.connectionMetadata);
    }
  }

  /// 从服务端返回的非敏感连接元数据反填表单字段。
  void _prefillCredentials(Map<String, String> metadata) {
    switch (_provider) {
      case 'S3':
        _s3ProviderType = metadata['provider'] ?? 'Minio';
        _s3AccessKeyCtrl.text = metadata['access_key_id'] ?? '';
        _s3EndpointCtrl.text = metadata['endpoint'] ?? '';
        _s3RegionCtrl.text = metadata['region'] ?? '';
      case 'WEBDAV':
        _webdavVendor = metadata['vendor'] ?? 'other';
        _webdavUrlCtrl.text = metadata['url'] ?? '';
        _webdavUserCtrl.text = metadata['user'] ?? '';
    }
  }

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _s3AccessKeyCtrl.dispose();
    _s3SecretKeyCtrl.dispose();
    _s3EndpointCtrl.dispose();
    _s3RegionCtrl.dispose();
    _webdavUrlCtrl.dispose();
    _webdavUserCtrl.dispose();
    _webdavPassCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_displayNameCtrl.text.trim().isEmpty) return false;
    if (_oauthAppMissing) return false;
    if (_isOAuthProvider) return true;
    final canKeepSecret = widget.account?.credentialsConfigured == true;
    // AWS 官方 S3 无需自定义端点，其余 S3 兼容服务必须提供端点。
    final endpointRequired = _s3ProviderType != 'AWS';
    return switch (_provider) {
      'S3' =>
        _s3AccessKeyCtrl.text.trim().isNotEmpty &&
            (canKeepSecret || _s3SecretKeyCtrl.text.trim().isNotEmpty) &&
            (!endpointRequired || _s3EndpointCtrl.text.trim().isNotEmpty),
      'WEBDAV' =>
        _webdavUrlCtrl.text.trim().isNotEmpty &&
            _webdavUserCtrl.text.trim().isNotEmpty &&
            (canKeepSecret || _webdavPassCtrl.text.trim().isNotEmpty),
      _ => false,
    };
  }

  String _buildCredentialsJson() {
    final map = switch (_provider) {
      'S3' => {
        'provider': _s3ProviderType,
        'access_key_id': _s3AccessKeyCtrl.text.trim(),
        if (_s3SecretKeyCtrl.text.trim().isNotEmpty)
          'secret_access_key': _s3SecretKeyCtrl.text.trim(),
        // 编辑模式始终提交 endpoint 以支持显式清空；新建 AWS 留空时不提交该键。
        if (widget.account != null || _s3EndpointCtrl.text.trim().isNotEmpty)
          'endpoint': _s3EndpointCtrl.text.trim(),
        if (widget.account != null || _s3RegionCtrl.text.trim().isNotEmpty)
          'region': _s3RegionCtrl.text.trim(),
      },
      'WEBDAV' => {
        'vendor': _webdavVendor,
        'url': _webdavUrlCtrl.text.trim(),
        'user': _webdavUserCtrl.text.trim(),
        if (_webdavPassCtrl.text.trim().isNotEmpty)
          'pass': _webdavPassCtrl.text.trim(),
      },
      // OAuth 连接的凭据只能通过授权流程获得，创建时提交空结构。
      _ => <String, String>{},
    };
    return jsonEncode(map);
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop((
      provider: _provider,
      displayName: _displayNameCtrl.text.trim(),
      credentialsJson: _buildCredentialsJson(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.account != null;
    return AlertDialog(
      title: Text(
        isEdit ? l10n.filesEditExternalStorage : l10n.filesAddExternalStorage,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDropdown<String>(
                  value: _provider,
                  label: l10n.filesStorageType,
                  items: [
                    if (widget.connectors.isNotEmpty)
                      for (final connector in widget.connectors)
                        AppDropdownItem(
                          value: connector.code,
                          label: connector.displayName,
                        )
                    else
                      for (final e in _providerLabels(l10n).entries)
                        AppDropdownItem(value: e.key, label: e.value),
                  ],
                  onChanged:
                      isEdit
                          ? null
                          : (value) {
                            if (value != null) {
                              setState(() => _provider = value);
                            }
                          },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _displayNameCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.filesDisplayName,
                    hintText: l10n.filesDisplayNameHint,
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (_oauthAppMissing) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.filesOAuthAppMissing,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.filesColors.error,
                    ),
                  ),
                ],
                // OAuth 连接不在此表单收集任何凭据，保存后通过授权流程获取 token。
                if (!_isOAuthProvider) ...[
                  const SizedBox(height: 16),
                  Text(
                    l10n.filesConnectionCredentials,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: context.filesColors.onSurfaceVariant,
                    ),
                  ),
                  if (isEdit &&
                      widget.account?.credentialsConfigured == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      l10n.filesExistingSecretPreserved,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.filesColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ..._buildCredentialFields(),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.filesCancel),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(isEdit ? l10n.filesSave : l10n.filesAddExternalStorage),
        ),
      ],
    );
  }

  List<Widget> _buildCredentialFields() {
    final l10n = AppLocalizations.of(context);
    return switch (_provider) {
      'S3' => [
        AppDropdown<String>(
          value: _s3ProviderType,
          label: l10n.filesS3Provider,
          items: [
            for (final e in _s3ProviderTypes)
              AppDropdownItem(value: e, label: e),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _s3ProviderType = v);
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _s3AccessKeyCtrl,
          decoration: InputDecoration(
            labelText: l10n.filesAccessKeyId,
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _s3SecretKeyCtrl,
          decoration: InputDecoration(
            labelText: l10n.filesSecretAccessKey,
            hintText:
                widget.account == null
                    ? null
                    : l10n.filesKeepExistingSecretHint,
            isDense: true,
          ),
          obscureText: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _s3EndpointCtrl,
          decoration: InputDecoration(
            labelText:
                _s3ProviderType == 'AWS'
                    ? l10n.filesEndpoint
                    : l10n.filesEndpointRequired,
            hintText: _s3ProviderType == 'AWS' ? null : l10n.filesEndpointHint,
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _s3RegionCtrl,
          decoration: InputDecoration(
            labelText: l10n.filesRegion,
            hintText: l10n.filesRegionHint,
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
      'WEBDAV' => [
        AppDropdown<String>(
          value: _webdavVendor,
          label: l10n.filesServiceType,
          items: [
            for (final e in _webdavVendors) AppDropdownItem(value: e, label: e),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _webdavVendor = v);
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _webdavUrlCtrl,
          decoration: InputDecoration(
            labelText: l10n.filesWebdavUrl,
            hintText: 'https://dav.example.com/dav/',
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _webdavUserCtrl,
          decoration: InputDecoration(
            labelText: l10n.filesUsername,
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _webdavPassCtrl,
          decoration: InputDecoration(
            labelText: l10n.filesPasswordOrApp,
            hintText:
                widget.account == null
                    ? null
                    : l10n.filesKeepExistingSecretHint,
            isDense: true,
          ),
          obscureText: true,
          onChanged: (_) => setState(() {}),
        ),
      ],
      'ONEDRIVE' || 'GDRIVE' || 'GOOGLE_DRIVE' || 'DROPBOX' => const <Widget>[],
      _ => [Text(l10n.filesUnknownStorageType)],
    };
  }
}
