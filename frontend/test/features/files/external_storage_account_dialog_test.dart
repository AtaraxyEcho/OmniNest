import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/presentation/widgets/external_storage_account_dialog.dart';

void main() {
  testWidgets('外部存储表单提交结构化 S3 凭据', (tester) async {
    ({String provider, String displayName, String credentialsJson})? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder:
                (context) => FilledButton(
                  onPressed: () async {
                    result = await showDialog(
                      context: context,
                      builder: (_) => const ExternalStorageAccountDialog(),
                    );
                  },
                  child: const Text('打开'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(5));
    await tester.enterText(fields.at(0), '家庭对象存储');
    await tester.enterText(fields.at(1), 'access-key');
    await tester.enterText(fields.at(2), 'secret-key');
    await tester.enterText(fields.at(3), 'https://storage.example.com');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '添加外部存储'));
    await tester.pumpAndSettle();

    expect(result?.provider, 'S3');
    expect(result?.displayName, '家庭对象存储');
    expect(jsonDecode(result!.credentialsJson), {
      'provider': 'Minio',
      'access_key_id': 'access-key',
      'secret_access_key': 'secret-key',
      'endpoint': 'https://storage.example.com',
    });
  });

  testWidgets('AWS 官方 S3 不填端点即可提交且不提交端点键', (tester) async {
    ({String provider, String displayName, String credentialsJson})? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder:
                (context) => FilledButton(
                  onPressed: () async {
                    result = await showDialog(
                      context: context,
                      builder: (_) => const ExternalStorageAccountDialog(),
                    );
                  },
                  child: const Text('打开'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 切换 S3 提供商到 AWS
    await tester.tap(find.text('Minio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AWS').last);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'AWS 生产桶');
    await tester.enterText(fields.at(1), 'aws-access-key');
    await tester.enterText(fields.at(2), 'aws-secret-key');
    await tester.pump();

    // 端点留空仍可提交
    await tester.tap(find.widgetWithText(FilledButton, '添加外部存储'));
    await tester.pumpAndSettle();

    expect(result?.provider, 'S3');
    final credentials = jsonDecode(result!.credentialsJson) as Map;
    expect(credentials['provider'], 'AWS');
    expect(credentials['access_key_id'], 'aws-access-key');
    expect(credentials['secret_access_key'], 'aws-secret-key');
    expect(credentials, isNot(contains('endpoint')));
  });

  testWidgets('编辑外部存储时反填连接元数据并保留已有密钥', (tester) async {
    ({String provider, String displayName, String credentialsJson})? result;
    const account = ExternalStorageAccount(
      id: 'storage-id',
      provider: 'S3',
      displayName: '家庭对象存储',
      connectionMetadata: {
        'provider': 'Minio',
        'access_key_id': 'saved-access-key',
        'endpoint': 'https://storage.example.com',
        'region': 'cn-east-1',
      },
      credentialsConfigured: true,
      status: 'ACTIVE',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder:
                (context) => FilledButton(
                  onPressed: () async {
                    result = await showDialog(
                      context: context,
                      builder:
                          (_) => const ExternalStorageAccountDialog(
                            account: account,
                          ),
                    );
                  },
                  child: const Text('编辑'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(5));
    expect(find.text('家庭对象存储'), findsOneWidget);
    expect(find.text('saved-access-key'), findsOneWidget);
    expect(find.text('https://storage.example.com'), findsOneWidget);
    expect(find.text('cn-east-1'), findsOneWidget);
    expect(find.text('留空以保留已保存的值'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final credentials = jsonDecode(result!.credentialsJson) as Map;
    expect(credentials['access_key_id'], 'saved-access-key');
    expect(credentials['endpoint'], 'https://storage.example.com');
    expect(credentials['region'], 'cn-east-1');
    expect(credentials, isNot(contains('secret_access_key')));
  });

  testWidgets('OAuth 连接仅填写显示名称并提交空凭据', (tester) async {
    ({String provider, String displayName, String credentialsJson})? result;
    const account = ExternalStorageAccount(
      id: 'storage-id',
      provider: 'GDRIVE',
      displayName: '我的云端硬盘',
      connectionMetadata: {},
      credentialsConfigured: false,
      status: 'ACTIVE',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder:
                (context) => FilledButton(
                  onPressed: () async {
                    result = await showDialog(
                      context: context,
                      builder:
                          (_) => const ExternalStorageAccountDialog(
                            account: account,
                          ),
                    );
                  },
                  child: const Text('编辑'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    // OAuth 类型不收集任何凭据，只剩显示名称输入框
    final fields = find.byType(TextField);
    expect(fields, findsOneWidget);
    expect(find.text('连接凭据'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(result?.provider, 'GDRIVE');
    expect(result?.displayName, '我的云端硬盘');
    expect(jsonDecode(result!.credentialsJson), {});
  });

  testWidgets('OAuth 连接器未配置应用时禁用提交并给出指引', (tester) async {
    ({String provider, String displayName, String credentialsJson})? result;
    const connectors = [
      ExternalStorageConnector(
        code: 'S3',
        displayName: 'S3',
        authMode: 'ACCESS_KEY',
      ),
      ExternalStorageConnector(
        code: 'WEBDAV',
        displayName: 'WebDAV',
        authMode: 'PASSWORD',
      ),
      ExternalStorageConnector(
        code: 'GDRIVE',
        displayName: 'Google Drive',
        authMode: 'OAUTH2',
        oauthConfigured: false,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.from(AppThemePalette.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder:
                (context) => FilledButton(
                  onPressed: () async {
                    result = await showDialog(
                      context: context,
                      builder:
                          (_) => const ExternalStorageAccountDialog(
                            connectors: connectors,
                          ),
                    );
                  },
                  child: const Text('打开'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 切到未配置的 Google Drive：出现警告且提交被拒
    await tester.tap(find.text('S3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Drive').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '云端硬盘');
    await tester.pump();

    expect(
      find.text('该类型需要管理员先在管理后台的外部存储页面配置 OAuth 应用，当前尚未配置，暂不能创建。'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, '添加外部存储'));
    await tester.pumpAndSettle();
    expect(result, isNull);

    // 切回具备条件的 WebDAV：警告消失
    await tester.tap(find.text('Google Drive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WebDAV').last);
    await tester.pumpAndSettle();
    expect(
      find.text('该类型需要管理员先在管理后台的外部存储页面配置 OAuth 应用，当前尚未配置，暂不能创建。'),
      findsNothing,
    );
  });
}
