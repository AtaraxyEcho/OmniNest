import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/reader/application/reader_parsed_book_cache.dart';
import 'package:omninest/features/reader/domain/parsed_book.dart';

void main() {
  test('解析书籍缓存按最近访问顺序淘汰', () {
    final cache = ReaderParsedBookCache(
      ownerUserId: 'reader-user',
      maxEntries: 2,
    );
    const first = ParsedBook(chapters: <ParsedChapter>[], title: 'First');
    const second = ParsedBook(chapters: <ParsedChapter>[], title: 'Second');
    const third = ParsedBook(chapters: <ParsedChapter>[], title: 'Third');

    cache.write('first', first);
    cache.write('second', second);
    expect(cache.read('first'), same(first));

    cache.write('third', third);

    expect(cache.read('second'), isNull);
    expect(cache.read('first'), same(first));
    expect(cache.read('third'), same(third));
  });

  test('重复写入不会产生重复的访问顺序记录', () {
    final cache = ReaderParsedBookCache(
      ownerUserId: 'reader-user',
      maxEntries: 2,
    );
    const first = ParsedBook(chapters: <ParsedChapter>[], title: 'First');
    const updated = ParsedBook(chapters: <ParsedChapter>[], title: 'Updated');
    const second = ParsedBook(chapters: <ParsedChapter>[], title: 'Second');

    cache.write('first', first);
    cache.write('first', updated);
    cache.write('second', second);

    expect(cache.read('first'), same(updated));
    expect(cache.read('second'), same(second));
  });

  test('删除和清空会释放对应缓存条目', () {
    final cache = ReaderParsedBookCache(ownerUserId: 'reader-user');
    const book = ParsedBook(chapters: <ParsedChapter>[]);

    cache.write('first', book);
    cache.write('second', book);
    cache.remove('first');
    expect(cache.read('first'), isNull);

    cache.clear();
    expect(cache.read('second'), isNull);
  });

  test('认证用户变化时清空旧实例并创建新缓存', () async {
    late _TestAuthSessionNotifier authNotifier;
    final container = ProviderContainer.test(
      overrides: [
        authSessionProvider.overrideWith(() {
          authNotifier = _TestAuthSessionNotifier(_user('first-user'));
          return authNotifier;
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authSessionProvider.future);
    final firstCache = container.read(readerParsedBookCacheProvider);
    const book = ParsedBook(chapters: <ParsedChapter>[]);
    firstCache.write('book', book);

    authNotifier.replaceUser(_user('second-user'));
    await container.pump();
    final secondCache = container.read(readerParsedBookCacheProvider);

    expect(secondCache, isNot(same(firstCache)));
    expect(secondCache.ownerUserId, 'second-user');
    expect(firstCache.read('book'), isNull);
  });
}

UserProfile _user(String id) {
  return UserProfile(id: id, username: id, role: 'MEMBER');
}

class _TestAuthSessionNotifier extends AuthSessionNotifier {
  _TestAuthSessionNotifier(this._initialUser);

  final UserProfile _initialUser;

  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(user: _initialUser);
  }

  void replaceUser(UserProfile user) {
    state = AsyncData(AuthSessionState(user: user));
  }
}
