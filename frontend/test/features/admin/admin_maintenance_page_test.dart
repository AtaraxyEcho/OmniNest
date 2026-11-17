import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';

class _SessionNotifier extends AuthSessionNotifier {
  _SessionNotifier(this._permissions);

  final Set<String> _permissions;

  @override
  Future<AuthSessionState> build() async => AuthSessionState(
    user: UserProfile(
      id: 'user-1',
      username: 'admin',
      role: 'ADMIN',
      permissions: _permissions,
    ),
  );
}

const _sharePage = AdminPage<AdminFileShareLink>(
  items: [
    AdminFileShareLink(
      id: 'share-1',
      ownerUserId: 'user-1',
      ownerUsername: 'owner',
      resourceType: 'FOLDER',
      resourceId: 'node-1',
      resourceName: '素材',
      status: 'ACTIVE',
      accessCount: 2,
    ),
  ],
  page: 0,
  size: 20,
  totalElements: 1,
  totalPages: 1,
);

const _unavailablePage = AdminPage<AdminUnavailableMedia>(
  items: [
    AdminUnavailableMedia(
      videoItemId: 'video-1',
      fileNodeId: 'file-1',
      librarySourceId: 'source-1',
      title: '影片',
      availabilityStatus: 'MISSING',
      missingConfirmations: 2,
    ),
  ],
  page: 0,
  size: 20,
  totalElements: 1,
  totalPages: 1,
);

void main() {
  Future<void> pumpPage(WidgetTester tester, Set<String> permissions) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => _SessionNotifier(permissions)),
          adminShareLinksProvider.overrideWith(
            (ref, query) => Future.value(_sharePage),
          ),
          adminUnavailableMediaProvider.overrideWith(
            (ref, query) => Future.value(_unavailablePage),
          ),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(child: AdminMaintenancePage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('三类管理权限同时存在时渲染三块面板', (tester) async {
    await pumpPage(tester, {
      'system:user:manage',
      'photo:admin',
      'media:library:manage',
    });
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AdminMaintenancePage)),
    );

    expect(find.text(l10n.adminMaintenanceSharesTitle), findsOneWidget);
    expect(find.text('素材'), findsOneWidget);
    expect(find.text(l10n.adminMaintenancePhotoTitle), findsOneWidget);
    expect(find.text(l10n.adminMaintenanceUnavailableTitle), findsOneWidget);
    expect(find.text('影片'), findsOneWidget);
  });

  testWidgets('只有照片管理权限时只渲染地理库面板', (tester) async {
    await pumpPage(tester, {'photo:admin'});
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AdminMaintenancePage)),
    );

    expect(find.text(l10n.adminMaintenancePhotoTitle), findsOneWidget);
    expect(find.text(l10n.adminMaintenanceSharesTitle), findsNothing);
    expect(find.text(l10n.adminMaintenanceUnavailableTitle), findsNothing);
  });
}
