import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_preferences.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_video_session.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_api.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_bundled_asset.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_file_picker.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_repository.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';

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

/// 记录落盘次数并拖延每次写入，复现拖杆时「写库 + 远端 PATCH」的往返成本。
class _CountingBackdropRepository extends AppBackdropRepository {
  // 父类的位置参数名是私有字段 `_db`，跨库无法写成 super 形参。
  // ignore: use_super_parameters
  _CountingBackdropRepository(LocalDatabase database) : super(database);

  int saveCount = 0;

  @override
  Future<void> saveSettings(AppBackdropSettings settings) async {
    saveCount++;
    await Future<void>.delayed(const Duration(milliseconds: 8));
    await super.saveSettings(settings);
  }
}

class _FakeBundledAssetInstaller extends AppBackdropBundledAssetInstaller {
  @override
  Future<AppBackdropAsset?> install() async {
    final now = DateTime(2026);
    return AppBackdropAsset(
      id: bundledDefaultWallpaperId,
      path: bundledDefaultWallpaperAssetPath,
      title: 'OmniNest',
      mediaType: AppBackdropMediaType.image,
      sourceType: AppBackdropSourceType.bundled,
      fileSize: 100,
      modifiedAt: now,
      createdAt: now,
      updatedAt: now,
      thumbnailPath: bundledDefaultWallpaperPosterAssetPath,
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

    test('拖放入口按扩展名分流,不支持的条目记为格式错误且不上传', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final api = _MockBackdropApi();
      final uploaded = BackdropServerAsset(
        id: 'server-drop',
        title: 'clip',
        mediaType: 'video',
        status: 'READY',
        fileSize: 8,
        updatedAt: DateTime(2026),
      );
      final uploadedFiles = <BackdropPickedFile>[];
      when(() => api.list()).thenAnswer((_) async => const []);
      when(() => api.upload(any())).thenAnswer((invocation) async {
        uploadedFiles.add(
          invocation.positionalArguments.single as BackdropPickedFile,
        );
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
      await notifier.addDroppedBackdropFiles([
        XFile.fromData(
          Uint8List.fromList(List<int>.filled(8, 0)),
          path: 'D:/drops/clip.mp4',
        ),
        XFile.fromData(Uint8List.fromList([0]), path: 'D:/drops/notes.txt'),
      ]);

      final state = container.read(appBackdropControllerProvider).requireValue;
      expect(uploadedFiles, hasLength(1));
      expect(uploadedFiles.single.name, endsWith('clip.mp4'));
      expect(uploadedFiles.single.size, 8);
      expect(uploadedFiles.single.isStreamBased, isFalse);
      expect(state.uploading, isFalse);
      expect(state.failedUploads, hasLength(1));
      expect(state.failedUploads.single.title, endsWith('.txt'));
      expect(state.failedUploads.single.code, '8002');
    });

    test('上传进行中重复拖放不再发起请求', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final api = _MockBackdropApi();
      final gate = Completer<BackdropServerAsset>();
      var uploadCalls = 0;
      when(() => api.list()).thenAnswer((_) async => const []);
      when(() => api.upload(any())).thenAnswer((_) {
        uploadCalls++;
        return gate.future;
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
      final dropped = [
        XFile.fromData(
          Uint8List.fromList(List<int>.filled(4, 0)),
          path: 'D:/drops/clip.mp4',
        ),
      ];
      final firstBatch = notifier.addDroppedBackdropFiles(dropped);
      for (var round = 0; round < 5; round++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        container.read(appBackdropControllerProvider).requireValue.uploading,
        isTrue,
      );

      await notifier.addDroppedBackdropFiles(dropped);
      expect(uploadCalls, 1);

      gate.complete(
        BackdropServerAsset(
          id: 'server-drop',
          title: 'clip',
          mediaType: 'video',
          status: 'READY',
          fileSize: 4,
          updatedAt: DateTime(2026),
        ),
      );
      await firstBatch;
      expect(
        container.read(appBackdropControllerProvider).requireValue.uploading,
        isFalse,
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

  group('AppBackdropController 设置合并落盘', () {
    test('连续拖动只落最后一格，内存态全程跟手且不回弹', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = _CountingBackdropRepository(database);
      final api = _MockBackdropApi();
      when(() => api.list()).thenAnswer((_) async => const []);
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

      // 模拟一帧一格地拖到 20%：每次推送后内存态必须立刻到位，
      // 而不是排队等 20 次「写库 + 回读 + 远端 PATCH」。
      final drag = <Future<void>>[];
      for (var step = 1; step <= 20; step++) {
        drag.add(notifier.setDimAmount(step / 100));
        expect(
          container
              .read(appBackdropControllerProvider)
              .requireValue
              .settings
              .dimAmount,
          closeTo(step / 100, 1e-9),
        );
      }
      await Future.wait(drag);

      // 落盘收敛在最后一格；中间的 19 个值既不落库也不把滑柄拽回去。
      expect((await repository.loadSettings()).dimAmount, closeTo(0.20, 1e-9));
      expect(
        container
            .read(appBackdropControllerProvider)
            .requireValue
            .settings
            .dimAmount,
        closeTo(0.20, 1e-9),
      );
      expect(repository.saveCount, lessThan(20));
    });

    test('暗化 90% 与模糊 24px 落库后不再被截断回调', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      final repository = AppBackdropRepository(database);
      final api = _MockBackdropApi();
      when(() => api.list()).thenAnswer((_) async => const []);
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
      await notifier.setDimAmount(0.90);
      await notifier.setBlurAmount(24);

      final persisted = await repository.loadSettings();
      // 滑杆行程是 0-90% / 0-24px，领域层曾把上限写死成 0.86 / 18。
      expect(persisted.dimAmount, closeTo(0.90, 1e-9));
      expect(persisted.blurAmount, closeTo(24, 1e-9));
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
