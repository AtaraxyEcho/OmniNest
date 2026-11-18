/// 桌面壳层的路由表。
///
/// 壳层里的「同级空间切换」与「进内容详情」是两种导航语义：前者 go
/// （换掉整条栈，空间之间本就平级），后者 push（留得住来路）。集中在此
/// 定义，调用点不再散落字面量，也让路由改名只动一处。
abstract final class DesktopRoutes {
  static const String home = '/portal';
  static const String movies = '/video';
  static const String photos = '/photos';
  static const String music = '/music';
  static const String reader = '/reader';
  static const String files = '/files';
  static const String admin = '/admin';
  static const String settings = '/profile';
  static const String notifications = '/notifications';
  static const String nowPlaying = '/music/now-playing';
  static const String login = '/login';
  static const String serverSetup = '/server-setup';

  static const String moviesHistory = '/video?section=history';
  static const String filesFavorites = '/files?section=favorites';
  static const String filesRecent = '/files?section=recent';
  static const String filesStorage = '/files?section=storageStats';
  static const String settingsAppearance = '/profile?section=appearance';
  static const String settingsSecurity = '/profile?section=security';
  static const String settingsNotifications = '/profile?section=notifications';
  static const String settingsBackdrop = '/profile?section=backdrop';
  static const String adminOperations = '/admin/ops';

  static String movieDetail(String id) => '/video/$id';
  static String seriesDetail(String id) => '/video/series/$id';
  static String moviePlay(String id, {bool fromStart = false}) =>
      '/video/$id/play${fromStart ? '?fromStart=1' : ''}';
  static String photoDetail(String id) => '/photos/$id';
  static String photoAlbumDetail(String id) => '/photos/albums/$id';
  static String bookDetail(String id) => '/reader/items/$id';
  static String filePreview(String id) => '/files/preview/$id';
}
