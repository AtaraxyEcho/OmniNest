import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_preferences.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_scene_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_video_session.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_api.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_bundled_asset.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_file_picker.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_repository.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_scene_scope.dart';

const String _testOwnerId = '11111111-1111-1111-1111-111111111111';

class _MutableSessionNotifier extends AuthSessionNotifier {
  _MutableSessionNotifier(this.initialState);

  final AuthSessionState initialState;

  @override
  Future<AuthSessionState> build() async => initialState;
}

class _MockBackdropApi extends Mock implements BackdropApi {}

class _MockBackdropFilePicker extends Mock implements BackdropFilePicker {}

class _NoopBundledAssetInstaller extends AppBackdropBundledAssetInstaller {
  @override
  Future<AppBackdropAsset?> install() async => null;
}

class _FakeBundledAssetInstaller extends AppBackdropBundledAssetInstaller {
  @override
  Future<AppBackdropAsset?> install() async {
    final now = DateTime(2026);
    return AppBackdropAsset(
      id: bundledDefaultWallpaperId,
      path: 'assets/backdrops/default_wallpaper.jpg',
      title: 'OmniNest',
      mediaType: AppBackdropMediaType.image,
      sourceType: AppBackdropSourceType.bundled,
      fileSize: 100,
      modifiedAt: now,
      createdAt: now,
      updatedAt: now,
    );
  }
}

class _NoopBackdropPreferencesController extends BackdropPreferencesController {
  _NoopBackdropPreferencesController(this._repository);

  final AppBackdropRepository _repository;

  @override
  Future<AppBackdropSettings> build() async {
    return await _repository.loadSettings();
  }

  @override
  Future<void> save(AppBackdropSettings settings) async {
    await _repository.saveSettings(settings);
    state = AsyncData(settings);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      BackdropServerAsset(
        id: 'fallback',
        title: 'fallback',
        mediaType: 'image',
        status: 'READY',
        fileSize: 0,
      ),
    );
    registerFallbackValue(const BackdropPickedFile(name: 'fallback', size: 0));
  });

  group('AppBackdropController', () {
    test('服务端素材经缓存可选择并自动启用', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final api = _MockBackdropApi();
      final serverAsset = BackdropServerAsset(
        id: 'server-1',
        title: 'server',
        mediaType: 'image',
        status: 'READY',
        fileSize: 2048,
        updatedAt: DateTime(2026),
      );
      when(() => api.list()).thenAnswer((_) async => [serverAsset]);
      final container = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _NoopBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container.read(appBackdropControllerProvider.future);
      final notifier = container.read(appBackdropControllerProvider.notifier);
      await notifier.selectBackdrop('server-1');

      final selected =
          container.read(appBackdropControllerProvider).requireValue;
      expect(
        selected.backdrops.where(
          (backdrop) => backdrop.sourceType == AppBackdropSourceType.server,
        ),
        isNotEmpty,
      );
      expect(selected.settings.selectedBackdropId, 'server-1');
      expect(selected.settings.enabled, isTrue);
      expect(selected.hasActiveBackdrop, isTrue);
    });

    test('离线时保留服务端素材缓存', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final serverAsset = BackdropServerAsset(
        id: 'server-cached',
        title: 'cached',
        mediaType: 'image',
        status: 'READY',
        fileSize: 2048,
        updatedAt: DateTime(2026),
      );
      await repository.upsertServerAssets([serverAsset]);
      final api = _MockBackdropApi();
      when(() => api.list()).thenThrow(Exception('offline'));
      final container = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _NoopBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      final state = await container.read(appBackdropControllerProvider.future);

      expect(
        state.backdrops.where((backdrop) => backdrop.id == 'server-cached'),
        isNotEmpty,
      );
    });

    test('无任何选中时自动启用内置壁纸', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final api = _MockBackdropApi();
      when(() => api.list()).thenAnswer((_) async => const []);
      final container = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _FakeBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      final state = await container.read(appBackdropControllerProvider.future);

      expect(state.settings.enabled, isTrue);
      expect(state.settings.selectedBackdropId, bundledDefaultWallpaperId);
      expect(state.hasActiveBackdrop, isTrue);
    });

    test('清空背景库会调用服务端删除并清理本地缓存', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final serverAsset = BackdropServerAsset(
        id: 'server-clear',
        title: 'clear',
        mediaType: 'image',
        status: 'READY',
        fileSize: 2048,
        updatedAt: DateTime(2026),
      );
      await repository.upsertServerAssets([serverAsset]);
      final api = _MockBackdropApi();
      when(() => api.list()).thenAnswer((_) async => const []);
      when(() => api.deleteAll()).thenAnswer(
        (_) async => const BackdropDeleteAllResult(deleted: 1, failed: 0),
      );
      final container = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _NoopBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container.read(appBackdropControllerProvider.future);
      final notifier = container.read(appBackdropControllerProvider.notifier);
      await notifier.clearBackdrops();

      verify(() => api.deleteAll()).called(1);
      final state = container.read(appBackdropControllerProvider).requireValue;
      expect(
        state.backdrops.where(
          (backdrop) => backdrop.sourceType == AppBackdropSourceType.server,
        ),
        isEmpty,
      );
    });

    test('清空背景库服务端失败时保留本地缓存并提示', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final serverAsset = BackdropServerAsset(
        id: 'server-keep',
        title: 'keep',
        mediaType: 'image',
        status: 'READY',
        fileSize: 2048,
        updatedAt: DateTime(2026),
      );
      await repository.upsertServerAssets([serverAsset]);
      final api = _MockBackdropApi();
      when(() => api.list()).thenAnswer((_) async => [serverAsset]);
      when(
        () => api.deleteAll(),
      ).thenThrow(const AppException(code: '500', message: 'boom'));
      final container = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _NoopBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container.read(appBackdropControllerProvider.future);
      final notifier = container.read(appBackdropControllerProvider.notifier);
      await notifier.clearBackdrops();

      final state = container.read(appBackdropControllerProvider).requireValue;
      expect(
        state.backdrops.where((backdrop) => backdrop.id == 'server-keep'),
        isNotEmpty,
      );
      expect(state.message, AppBackdropMessage.deleteFailed);
    });

    test('删除返回素材不存在时按已删除幂等清理本地', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final serverAsset = BackdropServerAsset(
        id: 'server-del',
        title: 'del',
        mediaType: 'image',
        status: 'READY',
        fileSize: 2048,
        updatedAt: DateTime(2026),
      );
      await repository.upsertServerAssets([serverAsset]);
      final api = _MockBackdropApi();
      when(() => api.list()).thenAnswer((_) async => [serverAsset]);
      when(
        () => api.delete(any()),
      ).thenThrow(const AppException(code: '8001', message: '背景素材不存在'));
      final container = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _NoopBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container.read(appBackdropControllerProvider.future);
      final notifier = container.read(appBackdropControllerProvider.notifier);
      await notifier.removeBackdrop('server-del');

      final state = container.read(appBackdropControllerProvider).requireValue;
      expect(
        state.backdrops.where((backdrop) => backdrop.id == 'server-del'),
        isEmpty,
      );
      expect(state.message, isNot(AppBackdropMessage.deleteFailed));
    });

    test('删除其他错误仍保留本地并提示失败', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final serverAsset = BackdropServerAsset(
        id: 'server-keep-2',
        title: 'keep2',
        mediaType: 'image',
        status: 'READY',
        fileSize: 2048,
        updatedAt: DateTime(2026),
      );
      await repository.upsertServerAssets([serverAsset]);
      final api = _MockBackdropApi();
      when(() => api.list()).thenAnswer((_) async => [serverAsset]);
      when(
        () => api.delete(any()),
      ).thenThrow(const AppException(code: '500', message: 'boom'));
      final container = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _NoopBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container.read(appBackdropControllerProvider.future);
      final notifier = container.read(appBackdropControllerProvider.notifier);
      await notifier.removeBackdrop('server-keep-2');

      final state = container.read(appBackdropControllerProvider).requireValue;
      expect(
        state.backdrops.where((backdrop) => backdrop.id == 'server-keep-2'),
        isNotEmpty,
      );
      expect(state.message, AppBackdropMessage.deleteFailed);
    });

    test('桌面端改选隔离壁纸不会覆盖移动端槽位', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final desktopBackdrop = _backdrop('desktop');
      final mobileBackdrop = _backdrop('mobile');
      await repository.upsertBackdrops([desktopBackdrop, mobileBackdrop]);
      await repository.saveSettings(
        const AppBackdropSettings(selectedBackdropId: 'mobile'),
      );
      final api = _MockBackdropApi();
      when(() => api.list()).thenAnswer((_) async => const []);
      final desktopContainer = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _NoopBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
          appBackdropSelectionTargetProvider.overrideWithValue(
            AppBackdropSelectionTarget.desktop,
          ),
        ],
      );
      final mobileContainer = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _NoopBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
          appBackdropSelectionTargetProvider.overrideWithValue(
            AppBackdropSelectionTarget.mobile,
          ),
        ],
      );
      addTearDown(() async {
        desktopContainer.dispose();
        mobileContainer.dispose();
        await database.close();
      });

      await desktopContainer.read(appBackdropControllerProvider.future);
      final notifier = desktopContainer.read(
        appBackdropControllerProvider.notifier,
      );
      await notifier.setDeviceSeparation(true);
      await notifier.selectBackdrop(desktopBackdrop.id);

      final state =
          desktopContainer.read(appBackdropControllerProvider).requireValue;
      expect(state.selectedBackdrop?.id, desktopBackdrop.id);
      expect(state.settings.desktopBackdropId, desktopBackdrop.id);
      expect(state.settings.mobileBackdropId, mobileBackdrop.id);

      final mobileState = await mobileContainer.read(
        appBackdropControllerProvider.future,
      );
      expect(mobileState.selectedBackdrop?.id, mobileBackdrop.id);
    });
  });

  group('AppBackdropController uploads', () {
    test('上传成功写入缓存并清除失败记录', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final api = _MockBackdropApi();
      final picker = _MockBackdropFilePicker();
      final uploaded = BackdropServerAsset(
        id: 'server-up',
        title: 'up',
        mediaType: 'image',
        status: 'READY',
        fileSize: 2048,
        updatedAt: DateTime(2026),
      );
      when(() => picker.pick()).thenAnswer(
        (_) async => [
          const BackdropPickedFile(name: 'a.png', size: 2048, path: 'D:/a.png'),
        ],
      );
      var uploadCalls = 0;
      when(() => api.list()).thenAnswer((_) async => const []);
      when(() => api.upload(any())).thenAnswer((_) async {
        uploadCalls++;
        return uploaded;
      });
      final container = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _NoopBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          appBackdropFilePickerProvider.overrideWithValue(picker),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container.read(appBackdropControllerProvider.future);
      final notifier = container.read(appBackdropControllerProvider.notifier);
      await notifier.addBackdropFiles();

      final state = container.read(appBackdropControllerProvider).requireValue;
      expect(state.uploading, isFalse);
      expect(state.failedUploads, isEmpty);
      expect(
        state.backdrops.where((backdrop) => backdrop.id == 'server-up'),
        isNotEmpty,
      );
      expect(uploadCalls, 1);
    });

    test('业务失败记录错误码且不自动重试', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final api = _MockBackdropApi();
      final picker = _MockBackdropFilePicker();
      when(() => picker.pick()).thenAnswer(
        (_) async => [
          const BackdropPickedFile(name: 'a.png', size: 2048, path: 'D:/a.png'),
        ],
      );
      var uploadCalls = 0;
      when(() => api.list()).thenAnswer((_) async => const []);
      when(() => api.upload(any())).thenAnswer((_) async {
        uploadCalls++;
        throw const AppException(code: '8003', message: '配额不足');
      });
      final container = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _NoopBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          appBackdropFilePickerProvider.overrideWithValue(picker),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container.read(appBackdropControllerProvider.future);
      final notifier = container.read(appBackdropControllerProvider.notifier);
      await notifier.addBackdropFiles();

      final state = container.read(appBackdropControllerProvider).requireValue;
      expect(state.uploading, isFalse);
      expect(state.failedUploads, hasLength(1));
      expect(state.failedUploads.single.code, '8003');
      expect(uploadCalls, 1);
    });

    test('网络类失败自动重试一次', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final api = _MockBackdropApi();
      final picker = _MockBackdropFilePicker();
      when(() => picker.pick()).thenAnswer(
        (_) async => [
          const BackdropPickedFile(name: 'a.png', size: 2048, path: 'D:/a.png'),
        ],
      );
      var uploadCalls = 0;
      when(() => api.list()).thenAnswer((_) async => const []);
      when(() => api.upload(any())).thenAnswer((_) async {
        uploadCalls++;
        if (uploadCalls == 1) {
          throw const AppException(code: 'network_error', message: '断网');
        }
        return BackdropServerAsset(
          id: 'server-retry',
          title: 'retry',
          mediaType: 'image',
          status: 'READY',
          fileSize: 2048,
          updatedAt: DateTime(2026),
        );
      });
      final container = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _NoopBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          appBackdropFilePickerProvider.overrideWithValue(picker),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      await container.read(appBackdropControllerProvider.future);
      await container
          .read(appBackdropControllerProvider.notifier)
          .addBackdropFiles();

      final state = container.read(appBackdropControllerProvider).requireValue;
      expect(state.failedUploads, isEmpty);
      expect(uploadCalls, 2);
      expect(
        state.backdrops.where((backdrop) => backdrop.id == 'server-retry'),
        isNotEmpty,
      );
    });
  });

  group('AppBackdropVideoSession source identity', () {
    test('签名查询串变化视为同一资源', () {
      const a =
          'http://localhost:9000/derived/x/original.mp4?X-Amz-Signature=aaa';
      const b =
          'http://localhost:9000/derived/x/original.mp4?X-Amz-Signature=bbb';
      expect(
        AppBackdropVideoSession.sourceIdentityOf(a),
        AppBackdropVideoSession.sourceIdentityOf(b),
      );
      expect(
        AppBackdropVideoSession.sourceIdentityOf(a),
        'http://localhost:9000/derived/x/original.mp4',
      );
    });
  });

  group('AppBackdropController startup fallback', () {
    test('选中不可用时回落并启用内置壁纸', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      await repository.saveSettings(
        const AppBackdropSettings(
          enabled: true,
          selectedBackdropId: 'missing-server-asset',
        ),
      );
      final api = _MockBackdropApi();
      when(() => api.list()).thenAnswer((_) async => const []);
      final container = ProviderContainer.test(
        overrides: [
          appBackdropRepositoryProvider.overrideWithValue(repository),
          appBackdropBundledAssetInstallerProvider.overrideWithValue(
            _FakeBundledAssetInstaller(),
          ),
          authSessionProvider.overrideWith(
            () => _MutableSessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: _testOwnerId,
                  username: 'owner',
                  role: 'MEMBER',
                ),
              ),
            ),
          ),
          appBackdropApiProvider.overrideWithValue(api),
          backdropPreferencesProvider.overrideWith(
            () => _NoopBackdropPreferencesController(repository),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });

      final state = await container.read(appBackdropControllerProvider.future);

      expect(state.settings.selectedBackdropId, bundledDefaultWallpaperId);
      expect(state.settings.enabled, isTrue);
      expect(state.hasActiveBackdrop, isTrue);
    });
  });

  group('AppBackdropSceneController', () {
    test('工作页面策略隐藏背景并启用工作可读性', () {
      expect(AppBackdropPolicy.work.scene, AppBackdropScene.work);
      expect(AppBackdropPolicy.work.visible, isFalse);
      expect(
        AppBackdropPolicy.work.playbackMode,
        AppBackdropPlaybackMode.paused,
      );
      expect(
        AppBackdropPolicy.work.readabilityMode,
        AppBackdropReadabilityMode.work,
      );
      expect(AppBackdropPolicy.work.motionAllowed, isFalse);
    });

    test('媒体内容页面使用静态背景快照', () {
      expect(AppBackdropPolicy.staticContent.visible, isTrue);
      expect(
        AppBackdropPolicy.staticContent.playbackMode,
        AppBackdropPlaybackMode.paused,
      );
      expect(AppBackdropPolicy.staticContent.motionAllowed, isFalse);
    });

    test('最近激活场景释放后回退到上一场景', () {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final controller = container.read(
        appBackdropSceneControllerProvider.notifier,
      );

      controller.request('portal', AppBackdropPolicy.portal);
      controller.request('music', AppBackdropPolicy.musicDeck);

      expect(
        container.read(appBackdropSceneControllerProvider).policy.scene,
        AppBackdropScene.musicDeck,
      );

      controller.release('music');

      final state = container.read(appBackdropSceneControllerProvider);
      expect(state.owner, 'portal');
      expect(state.policy.scene, AppBackdropScene.portal);
    });

    test('过期租约不能释放同一所有者的新场景', () {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      final controller = container.read(
        appBackdropSceneControllerProvider.notifier,
      );

      final oldLease = controller.request('music', AppBackdropPolicy.portal);
      controller.request('music', AppBackdropPolicy.musicDeck);
      controller.release('music', lease: oldLease);

      final state = container.read(appBackdropSceneControllerProvider);
      expect(state.owner, 'music');
      expect(state.policy.scene, AppBackdropScene.musicDeck);
    });

    testWidgets('场景作用域卸载时在当前帧结束后释放场景', (tester) async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AppBackdropSceneScope(
              owner: 'music',
              policy: AppBackdropPolicy.musicDeck,
              child: SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(container.read(appBackdropSceneControllerProvider).owner, 'music');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      await tester.pump();
      // 空策略宽限在 post-frame release 之后再经微任务落到 hidden。
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(container.read(appBackdropSceneControllerProvider).owner, isNull);
    });

    test('视频会话 Provider 在同一容器内保持单实例', () {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);

      final first = container.read(appBackdropVideoSessionProvider);
      final second = container.read(appBackdropVideoSessionProvider);

      expect(identical(first, second), isTrue);
      expect(first.diagnostics.textureCount, 0);
      expect(first.diagnostics.successfulOpenCount, 0);
    });
  });
}

AppBackdropAsset _backdrop(String id) {
  return AppBackdropAsset(
    id: id,
    path: '',
    title: id,
    mediaType: AppBackdropMediaType.image,
    sourceType: AppBackdropSourceType.server,
    fileSize: 1024,
    modifiedAt: DateTime(2026),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}
