import 'package:cached_network_image/cached_network_image.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/photos_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/photos/application/photo_controller.dart';
import 'package:omninest/features/photos/domain/photo_share_link.dart';

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

  @override
  void initState() {
    super.initState();
    _loadAlbum();
  }

  Future<void> _loadAlbum() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = ref.read(photoCenterControllerProvider.notifier);
      final sessionToken = await controller.authorizeSharedAlbum(
        widget.token,
        password: _password,
      );
      if (!mounted || generation != _loadGeneration) return;
      final album = await controller.accessSharedAlbum(
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
      // 后端密码校验失败返回 400 +「密码错误」文案；据此进入密码流程，
      // 并在二次输入失败时给出可区分的错误提示。
      final msg = e.toString();
      if (msg.contains('password') || msg.contains('密码')) {
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

  Widget _buildBody() {
    if (_loading) return const AppLoading.grid();

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

    return _SharedAlbumContent(album: _album!);
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
      child: Container(
        width: 360,
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
    );
  }
}

/// 共享相册内容
class _SharedAlbumContent extends StatelessWidget {
  const _SharedAlbumContent({required this.album});

  final PhotoSharedAlbum album;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部栏
        Container(
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: 24),
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
                AppLocalizations.of(
                  context,
                ).photosPhotoCount(album.photos.length),
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
                      return GridView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                        itemCount: album.photos.length,
                        itemBuilder: (context, index) {
                          final photo = album.photos[index];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child:
                                photo.hasCover
                                    ? CachedNetworkImage(
                                      imageUrl: photo.coverUrl!,
                                      fit: BoxFit.cover,
                                      placeholder:
                                          (context, url) => Container(
                                            color:
                                                context
                                                    .photosColors
                                                    .surfaceContainerHigh,
                                          ),
                                      errorWidget:
                                          (context, url, error) => Icon(
                                            Icons.broken_image_outlined,
                                            color:
                                                context
                                                    .photosColors
                                                    .onSurfaceVariant,
                                          ),
                                    )
                                    : Container(
                                      color:
                                          context
                                              .photosColors
                                              .surfaceContainerHigh,
                                      child: Icon(
                                        Icons.photo_outlined,
                                        color:
                                            context
                                                .photosColors
                                                .onSurfaceVariant,
                                      ),
                                    ),
                          );
                        },
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
