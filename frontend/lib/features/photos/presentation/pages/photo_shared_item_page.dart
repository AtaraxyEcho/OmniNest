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
import 'package:omninest/features/photos/domain/photo.dart';

/// 公开共享单张照片页面（无需登录）
class PhotoSharedItemPage extends ConsumerStatefulWidget {
  const PhotoSharedItemPage({required this.token, super.key});

  final String token;

  @override
  ConsumerState<PhotoSharedItemPage> createState() =>
      _PhotoSharedItemPageState();
}

class _PhotoSharedItemPageState extends ConsumerState<PhotoSharedItemPage> {
  String? _password;
  bool _needPassword = false;
  String? _passwordError;
  PhotoItem? _photo;
  Object? _error;
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = ref.read(photoCenterControllerProvider.notifier);
      final sessionToken = await controller.authorizeSharedPhoto(
        widget.token,
        password: _password,
      );
      if (!mounted || generation != _loadGeneration) return;
      final photo = await controller.accessSharedPhoto(
        widget.token,
        sessionToken: sessionToken,
      );
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _photo = photo;
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
        message: describeUserFacingError(_error!).displayMessage,
        onRetry: _loadPhoto,
      );
    }

    if (_needPassword) {
      return _SharedItemPasswordPrompt(
        errorText: _passwordError,
        onSubmit: (password) {
          _password = password;
          _loadPhoto();
        },
      );
    }

    final photo = _photo;
    if (photo == null) return const SizedBox.shrink();

    return _SharedItemContent(photo: photo);
  }
}

/// 密码输入提示（单张照片分享）
class _SharedItemPasswordPrompt extends StatefulWidget {
  const _SharedItemPasswordPrompt({required this.onSubmit, this.errorText});

  final ValueChanged<String> onSubmit;
  final String? errorText;

  @override
  State<_SharedItemPasswordPrompt> createState() =>
      _SharedItemPasswordPromptState();
}

class _SharedItemPasswordPromptState extends State<_SharedItemPasswordPrompt> {
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
                AppLocalizations.of(context).photosSharedItemPasswordRequired,
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

/// 共享照片内容：单张大图 + 标题
class _SharedItemContent extends StatelessWidget {
  const _SharedItemContent({required this.photo});

  final PhotoItem photo;

  @override
  Widget build(BuildContext context) {
    final imageUrl = photo.sourceUrl ?? photo.coverUrl;
    return Column(
      children: [
        // 顶部栏：Scaffold body 不自动避让状态栏，分享页在手机上需自行加高。
        Container(
          height: 64 + MediaQuery.paddingOf(context).top,
          padding: EdgeInsets.only(
            left: 24,
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
              Icon(
                Icons.photo_rounded,
                color: context.photosColors.primaryContainer,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  photo.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.photosColors.onSurface,
                    fontSize: AppTypography.titleMedium,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 照片大图
        Expanded(
          child: Container(
            color: context.photosColors.surfaceContainerLow,
            padding: const EdgeInsets.all(24),
            child: Center(
              child:
                  imageUrl != null && imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder:
                            (context, url) => Center(
                              child: CircularProgressIndicator(
                                color: context.photosColors.primaryContainer,
                                strokeWidth: 2.5,
                              ),
                            ),
                        errorWidget:
                            (context, url, error) => Icon(
                              Icons.broken_image_outlined,
                              color: context.photosColors.onSurfaceVariant,
                              size: 48,
                            ),
                      )
                      : Icon(
                        Icons.photo_outlined,
                        color: context.photosColors.onSurfaceVariant,
                        size: 48,
                      ),
            ),
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
