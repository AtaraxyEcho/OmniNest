import 'package:cached_network_image/cached_network_image.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';
import 'package:omninest/core/utils/download_url_opener.dart';
import 'package:omninest/core/utils/image_decode_width.dart';
import 'package:omninest/core/utils/route_exit.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/core/widgets/infinite_scroll.dart';
import 'package:omninest/features/photos/application/photo_repository_providers.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_thumb_image.dart';

/// 公开共享相册页面（无需登录）
class PhotoSharedAlbumPage extends ConsumerStatefulWidget {
  const PhotoSharedAlbumPage({required this.token, super.key});

  final String token;

  @override
  ConsumerState<PhotoSharedAlbumPage> createState() =>
      _PhotoSharedAlbumPageState();
}

class _PhotoSharedAlbumPageState extends ConsumerState<PhotoSharedAlbumPage> {
  String? _password;
  bool _needPassword = false;
  String? _passwordError;
  PhotoSharedAlbum? _album;
  Object? _error;
  bool _loading = true;
  int _loadGeneration = 0;

  /// 访客会话令牌：续页复用，避免每次触底都重新走密码授权。
  String? _sessionToken;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadAlbum();
  }

  /// 共享相册续页：页码递增追加以 id 去重，失败静默等待下次触底。
  Future<void> _loadMore() async {
    final album = _album;
    if (album == null || !album.hasMore || _loadingMore) {
      return;
    }
    _loadingMore = true;
    try {
      final next = await _accessSharedPage(album.page + 1, album.size);
      if (!mounted) {
        return;
      }
      final seen = album.photos.map((photo) => photo.id).toSet();
      setState(() {
        _album = PhotoSharedAlbum(
          albumName: album.albumName,
          description: album.description,
          photos: <PhotoItem>[
            ...album.photos,
            ...next.photos.where((photo) => !seen.contains(photo.id)),
          ],
          page: next.page,
          size: next.size,
          total: next.total,
        );
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      // 会话过期与网络失败都不能静默：访客会误以为相册到底了。
      showOmniFeedback(
        context,
        AppLocalizations.of(context).photosSharedAlbumLoadMoreFailed(
          describeUserFacingError(error).displayMessage,
        ),
        severity: OmniFeedbackSeverity.error,
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// 读取共享相册分页；访客会话过期时自动重新授权一次再重试。
  Future<PhotoSharedAlbum> _accessSharedPage(int page, int size) async {
    final repo = ref.read(photoRepositoryProvider);
    var sessionToken = _sessionToken;
    if (sessionToken == null) {
      sessionToken = await repo.authorizeSharedAlbum(
        widget.token,
        password: _password,
      );
      _sessionToken = sessionToken;
    }
    try {
      return await repo.accessSharedAlbum(
        widget.token,
        sessionToken: sessionToken,
        page: page,
        size: size,
      );
    } on Object catch (error) {
      final code = describeUserFacingError(error).code;
      final expired =
          code == AppErrorCodes.shareSessionInvalid || code == 'UNAUTHORIZED';
      if (!expired) {
        rethrow;
      }
      final renewed = await repo.authorizeSharedAlbum(
        widget.token,
        password: _password,
      );
      _sessionToken = renewed;
      return repo.accessSharedAlbum(
        widget.token,
        sessionToken: renewed,
        page: page,
        size: size,
      );
    }
  }

  Future<void> _loadAlbum() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(photoRepositoryProvider);
      final sessionToken = await repo.authorizeSharedAlbum(
        widget.token,
        password: _password,
      );
      if (!mounted || generation != _loadGeneration) return;
      _sessionToken = sessionToken;
      final album = await repo.accessSharedAlbum(
        widget.token,
        sessionToken: sessionToken,
        page: 0,
        size: 50,
      );
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _album = album;
        _loading = false;
        _needPassword = false;
        _passwordError = null;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      // 稳定错误码判断是否进入密码流程，避免依赖服务端文案。
      final code = describeUserFacingError(e).code;
      if (_isSharePasswordError(code)) {
        setState(() {
          _needPassword = true;
          _loading = false;
          _passwordError =
              _password == null || _password!.isEmpty
                  ? null
                  : describeUserFacingError(e).displayMessage;
        });
      } else {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  static bool _isSharePasswordError(String? code) {
    return code == AppErrorCodes.needPassword ||
        code == AppErrorCodes.passwordInvalid ||
        code == AppErrorCodes.sharePasswordRequired;
  }

  @override
  void dispose() {
    _loadGeneration++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.photosColors.surface,
      body: _buildBody(),
    );
  }

  /// 全屏预览覆盖层的当前下标；null 表示未打开。
  int? _lightboxIndex;

  Widget _buildBody() {
    if (_loading) return const AppLoading();

    if (_error != null) {
      return AppErrorView(
        message: AppLocalizations.of(context).photosSharedAlbumAccessError(
          describeUserFacingError(_error!).displayMessage,
        ),
        onRetry: _loadAlbum,
      );
    }

    if (_needPassword) {
      return _PasswordPrompt(
        errorText: _passwordError,
        onSubmit: (password) {
          _password = password;
          _loadAlbum();
        },
      );
    }

    if (_album == null) return const SizedBox.shrink();

    final album = _album!;
    final index = _lightboxIndex;
    return Stack(
      children: [
        _SharedAlbumContent(
          album: album,
          isLoadingMore: _loadingMore,
          onLoadMore: _loadMore,
          onOpenPhoto:
              (photoIndex) => setState(() => _lightboxIndex = photoIndex),
        ),
        if (index != null && index < album.photos.length)
          _SharedPhotoLightbox(
            photos: album.photos,
            index: index,
            total: album.total > 0 ? album.total : album.photos.length,
            onIndexChanged: (next) => setState(() => _lightboxIndex = next),
            onClose: () => setState(() => _lightboxIndex = null),
          ),
      ],
    );
  }
}

/// 密码输入提示
class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt({required this.onSubmit, this.errorText});

  final ValueChanged<String> onSubmit;
  final String? errorText;

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        // 手机宽度不足 360 时固定宽会横向溢出，改为上限。
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: context.photosColors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: context.photosColors.primaryContainer,
                size: 48,
              ),
              SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).photosSharedAlbumPasswordRequired,
                style: TextStyle(
                  color: context.photosColors.onSurface,
                  fontSize: AppTypography.titleMedium,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).photosSharedAlbumPasswordHint,
                style: TextStyle(
                  color: context.photosColors.onSurfaceVariant,
                  fontSize: AppTypography.bodyMedium,
                ),
              ),
              if (widget.errorText != null) ...[
                SizedBox(height: 8),
                Text(
                  widget.errorText!,
                  style: TextStyle(
                    color: context.photosColors.danger,
                    fontSize: AppTypography.bodyMedium,
                  ),
                ),
              ],
              SizedBox(height: 20),
              TextField(
                controller: _controller,
                obscureText: true,
                autofocus: true,
                style: TextStyle(color: context.photosColors.onSurface),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).photosEnterPassword,
                  hintStyle: TextStyle(
                    color: context.photosColors.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                  prefixIcon: const Icon(Icons.key_rounded, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onSubmitted: (v) {
                  if (v.isNotEmpty) widget.onSubmit(v);
                },
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final text = _controller.text.trim();
                    if (text.isNotEmpty) widget.onSubmit(text);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: context.photosColors.primaryContainer,
                    foregroundColor: context.photosColors.onPrimaryContainer,
                  ),
                  child: Text(AppLocalizations.of(context).photosAccess),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 共享相册内容
class _SharedAlbumContent extends StatelessWidget {
  const _SharedAlbumContent({
    required this.album,
    required this.onOpenPhoto,
    this.isLoadingMore = false,
    this.onLoadMore,
  });

  final PhotoSharedAlbum album;

  /// 点开某张：由宿主渲染页内全屏覆盖层（公开页不额外挂路由）。
  final ValueChanged<int> onOpenPhoto;

  /// 滚动加载：访客页续页由宿主 State 持有会话与门闩。
  final bool isLoadingMore;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部栏：Scaffold body 不自动避让状态栏，分享页在手机上需自行加高。
        Container(
          height: 64 + MediaQuery.paddingOf(context).top,
          padding: EdgeInsets.only(
            left: 8,
            right: 24,
            top: MediaQuery.paddingOf(context).top,
          ),
          decoration: BoxDecoration(
            color: context.photosColors.surfaceContainer.withValues(
              alpha: 0.70,
            ),
            border: Border(
              bottom: BorderSide(
                color: context.photosColors.outlineVariant.withValues(
                  alpha: 0.32,
                ),
              ),
            ),
          ),
          child: Row(
            children: [
              // 本页挂在应用壳层之外：桌面端没有浏览器后退键时，这是唯一退出入口。
              IconButton(
                tooltip: AppLocalizations.of(context).coreBackToPortal,
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed:
                    () => exitDetailRoute(context, fallbackRoute: '/portal'),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.photo_album_rounded,
                color: context.photosColors.primaryContainer,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.albumName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.photosColors.onSurface,
                        fontSize: AppTypography.titleMedium,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (album.description != null &&
                        album.description!.isNotEmpty)
                      Text(
                        album.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.photosColors.onSurfaceVariant,
                          fontSize: AppTypography.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                // 分享相册分页加载，标题数量必须取服务端总数，否则只显示当前页长度。
                AppLocalizations.of(context).photosPhotoCount(
                  album.total > 0 ? album.total : album.photos.length,
                ),
                style: TextStyle(
                  color: context.photosColors.onSurfaceVariant,
                  fontSize: AppTypography.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        // 照片网格
        Expanded(
          child:
              album.photos.isEmpty
                  ? Center(
                    child: Text(
                      AppLocalizations.of(context).photosAlbumEmpty,
                      style: TextStyle(
                        color: context.photosColors.onSurfaceVariant,
                      ),
                    ),
                  )
                  : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns =
                          constraints.maxWidth >= 1200
                              ? 6
                              : constraints.maxWidth >= 900
                              ? 5
                              : constraints.maxWidth >= 600
                              ? 4
                              : constraints.maxWidth >= 400
                              ? 3
                              : 2;
                      return InfiniteScrollTrigger(
                        enabled: album.hasMore && !isLoadingMore,
                        onLoadMore: onLoadMore ?? () {},
                        child: GridView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 1,
                              ),
                          itemCount: album.photos.length,
                          itemBuilder: (context, index) {
                            final photo = album.photos[index];
                            // 公开相册原本只能看缩略图：点开后页内覆盖层给大图与下载。
                            return InkWell(
                              onTap: () => onOpenPhoto(index),
                              child: Semantics(
                                label:
                                    AppLocalizations.of(
                                      context,
                                    ).photosOpenPhotoPreview,
                                button: true,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _SharedAlbumTile(
                                    photo: photo,
                                    decodeWidth: thumbnailDecodeWidth(
                                      (constraints.maxWidth -
                                              48 -
                                              8 * (columns - 1)) /
                                          columns,
                                      MediaQuery.devicePixelRatioOf(context),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
        ),
        // 底部
        Container(
          padding: EdgeInsets.all(12),
          child: Text(
            AppLocalizations.of(context).photosSharedPoweredBy,
            style: TextStyle(
              color: context.photosColors.onSurfaceVariant,
              fontSize: AppTypography.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

/// 共享相册网格瓦片：按列宽解码缩略图，无封面时给占位图标。
class _SharedAlbumTile extends StatelessWidget {
  const _SharedAlbumTile({required this.photo, required this.decodeWidth});

  final PhotoItem photo;

  /// 已按列宽与设备像素比算好的解码宽度，由网格侧统一计算。
  final int decodeWidth;

  @override
  Widget build(BuildContext context) {
    final coverUrl = photo.coverUrl;
    if (!photo.hasCover || coverUrl == null || coverUrl.isEmpty) {
      return Container(
        color: context.photosColors.surfaceContainerHigh,
        child: Icon(
          Icons.photo_outlined,
          color: context.photosColors.onSurfaceVariant,
        ),
      );
    }
    // 网格瓦片按实际列宽解码：公开相册页在宽屏下同时可见数十张，
    // 全分辨率解码会造成明显滚动与首帧卡顿。
    return CachedNetworkImage(
      imageUrl: coverUrl,
      memCacheWidth: decodeWidth,
      fit: BoxFit.cover,
      placeholder:
          (context, url) =>
              Container(color: context.photosColors.surfaceContainerHigh),
      errorWidget:
          (context, url, error) => Icon(
            Icons.broken_image_outlined,
            color: context.photosColors.onSurfaceVariant,
          ),
    );
  }
}

/// 公开相册的页内全屏预览覆盖层：大图、左右翻页与下载，不改分享令牌语义。
class _SharedPhotoLightbox extends StatefulWidget {
  const _SharedPhotoLightbox({
    required this.photos,
    required this.index,
    required this.total,
    required this.onIndexChanged,
    required this.onClose,
  });

  final List<PhotoItem> photos;
  final int index;
  final int total;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onClose;

  @override
  State<_SharedPhotoLightbox> createState() => _SharedPhotoLightboxState();
}

class _SharedPhotoLightboxState extends State<_SharedPhotoLightbox> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.index;
    _controller = PageController(initialPage: _index);
  }

  @override
  void didUpdateWidget(covariant _SharedPhotoLightbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == _index) {
      return;
    }
    _index = widget.index;
    if (!_controller.hasClients) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) {
        _controller.jumpToPage(_index);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int next) {
    if (next < 0 || next >= widget.photos.length) {
      return;
    }
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _goTo(_index - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _goTo(_index + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = widget.total > 0 ? widget.total : widget.photos.length;
    return Positioned.fill(
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKey,
        child: ColoredBox(
          color: const Color(0xF2000000),
          child: SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '${_index + 1} / $total',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip:
                          widget.photos[_index].sourceUrl == null
                              ? l10n.photosDownloadSourceUnavailable
                              : l10n.photosDownloadPhoto,
                      icon: const Icon(Icons.download_rounded),
                      color: Colors.white,
                      onPressed:
                          widget.photos[_index].sourceUrl == null
                              ? null
                              : () => _download(
                                context,
                                widget.photos[_index].sourceUrl!,
                                widget.photos[_index],
                              ),
                    ),
                    IconButton(
                      tooltip: l10n.corePrevious,
                      icon: const Icon(Icons.chevron_left_rounded),
                      color: Colors.white,
                      onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                    ),
                    IconButton(
                      tooltip: l10n.coreNext,
                      icon: const Icon(Icons.chevron_right_rounded),
                      color: Colors.white,
                      onPressed:
                          _index < widget.photos.length - 1
                              ? () => _goTo(_index + 1)
                              : null,
                    ),
                    IconButton(
                      tooltip: l10n.coreClose,
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: widget.photos.length,
                    onPageChanged: (next) {
                      setState(() => _index = next);
                      widget.onIndexChanged(next);
                    },
                    itemBuilder:
                        (context, photoIndex) =>
                            _buildPhoto(context, widget.photos[photoIndex]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto(BuildContext context, PhotoItem photo) {
    // 关闭原图质量时服务端不签发 sourceUrl：预览退回封面，下载入口隐藏。
    final displayUrl = photo.sourceUrl ?? photo.coverUrl;
    if (displayUrl == null || displayUrl.isEmpty) {
      return const Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: Colors.white54,
        ),
      );
    }
    return InteractiveViewer(
      child: Center(
        // 分享页大图同样按屏宽量化解码档位：手机浏览器直接解码
        // 高像素原图会卡住主线程并把位图堆满内存。
        child: CachedNetworkImage(
          imageUrl: displayUrl,
          fit: BoxFit.contain,
          memCacheWidth: quantizedDecodeWidth(
            logicalWidth: MediaQuery.sizeOf(context).width,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            step: 256,
            min: 512,
            max: 4096,
          ),
        ),
      ),
    );
  }

  /// 与文件夹分享同一口径：能开新标签就开，否则退回复制链接。
  Future<void> _download(
    BuildContext context,
    String url,
    PhotoItem photo,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (openDownloadUrl(url)) {
      return;
    }
    final copied = await copyTextToClipboard(url);
    if (!context.mounted) {
      return;
    }
    showOmniFeedback(
      context,
      copied ? l10n.filesDownloadLinkCopied : l10n.clipboardCopyFailed,
      severity:
          copied ? OmniFeedbackSeverity.success : OmniFeedbackSeverity.error,
    );
  }
}
