import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/application/file_download_url_provider.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/reader/application/reader_book_provider.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/domain/movie_models.dart';

void main() {
  test('不同参数的页面 Family Provider 在最后监听者释放后销毁', () async {
    final repository = _MockFileRepository();
    when(() => repository.downloadUrl(any())).thenAnswer((invocation) async {
      return 'https://example.test/${invocation.positionalArguments.first}';
    });
    final container = ProviderContainer.test(
      overrides: [fileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final firstProvider = fileDownloadUrlProvider('first');
    final secondProvider = fileDownloadUrlProvider('second');
    final firstSubscription = container.listen(
      firstProvider,
      (previous, next) {},
    );
    final secondSubscription = container.listen(
      secondProvider,
      (previous, next) {},
    );

    await Future.wait(<Future<String?>>[
      container.read(firstProvider.future),
      container.read(secondProvider.future),
    ]);
    expect(container.exists(firstProvider), isTrue);
    expect(container.exists(secondProvider), isTrue);

    firstSubscription.close();
    secondSubscription.close();
    await container.pump();

    expect(container.exists(firstProvider), isFalse);
    expect(container.exists(secondProvider), isFalse);
  });

  test('实时刷新参数集合随 Family Provider 生命周期回收', () async {
    final api = _MockMovieApi();
    final pending = Completer<MovieSeasonDetail>();
    when(
      () => api.seasonDetail(any(), any()),
    ).thenAnswer((_) => pending.future);
    final container = ProviderContainer.test(
      overrides: [movieApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    const firstKey = SeasonKey(seriesId: 'series', seasonNumber: 1);
    const secondKey = SeasonKey(seriesId: 'series', seasonNumber: 2);
    final firstSubscription = container.listen(
      movieSeasonDetailProvider(firstKey),
      (previous, next) {},
    );
    final secondSubscription = container.listen(
      movieSeasonDetailProvider(secondKey),
      (previous, next) {},
    );

    expect(container.read(activeMovieSeasonKeysProvider), <SeasonKey>{
      firstKey,
      secondKey,
    });

    firstSubscription.close();
    await container.pump();
    expect(container.read(activeMovieSeasonKeysProvider), <SeasonKey>{
      secondKey,
    });

    secondSubscription.close();
    await container.pump();
    expect(container.read(activeMovieSeasonKeysProvider), isEmpty);
  });

  test('EPUB Provider 销毁时释放解压 Archive', () async {
    final container = ProviderContainer.test();
    addTearDown(container.dispose);
    final provider = epubParserServiceProvider('reader-item');
    final subscription = container.listen(provider, (previous, next) {});
    final service = container.read(provider);
    final archive =
        Archive()..addFile(
          ArchiveFile(
            'mimetype',
            'application/epub+zip'.length,
            utf8.encode('application/epub+zip'),
          ),
        );
    final encoded = ZipEncoder().encode(archive);

    service.isFixedLayout(Uint8List.fromList(encoded));
    expect(service.cachedArchive, isNotNull);

    subscription.close();
    await container.pump();

    expect(container.exists(provider), isFalse);
    expect(service.cachedArchive, isNull);
  });
}

class _MockFileRepository extends Mock implements FileRepository {}

class _MockMovieApi extends Mock implements MovieApi {}
