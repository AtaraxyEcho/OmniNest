import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:flutter/material.dart';
import 'package:omninest/core/errors/error_message.dart';

String movieErrorMessage(Object error, [AppLocalizations? l10n]) {
  final userFacingError = describeUserFacingError(error);
  final localizedMessage = switch (userFacingError.code) {
    _ => null,
  };
  if (localizedMessage != null) {
    return localizedMessage;
  }
  final message = userFacingError.message.trim();
  return message.isEmpty
      ? (l10n?.videoOperationFailed ?? '操作失败，请稍后重试')
      : message;
}

void showMovieFeedback(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final theme = Theme.of(context);
  final backgroundColor =
      isError
          ? theme.colorScheme.errorContainer
          : context.videoColors.surfaceContainerHigh.withValues(alpha: 0.92);
  final foregroundColor =
      isError
          ? theme.colorScheme.onErrorContainer
          : context.videoColors.onSurface;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: TextStyle(color: foregroundColor)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: backgroundColor,
      duration: const Duration(seconds: 3),
    ),
  );
}

class MovieAsyncButton extends StatefulWidget {
  const MovieAsyncButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = false,
    this.style,
    this.loadingLabel,
    this.successMessage,
    this.enabled = true,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Future<void> Function() onPressed;
  final bool filled;
  final ButtonStyle? style;
  final String? loadingLabel;
  final String? successMessage;
  final bool enabled;

  @override
  State<MovieAsyncButton> createState() => _MovieAsyncButtonState();
}

class _MovieAsyncButtonState extends State<MovieAsyncButton> {
  bool _running = false;
  String? _errorMessage;
  bool _hovered = false;

  Future<void> _handlePressed() async {
    if (_running || !widget.enabled) {
      return;
    }
    setState(() {
      _running = true;
      _errorMessage = null;
    });
    try {
      await widget.onPressed();
      if (mounted && widget.successMessage != null) {
        showMovieFeedback(context, widget.successMessage!);
      }
    } catch (error) {
      final message = movieErrorMessage(error);
      if (mounted) {
        setState(() => _errorMessage = message);
        showMovieFeedback(context, message, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttonStyle = widget.style;
    final loadingLabel =
        widget.loadingLabel ?? AppLocalizations.of(context).videoProcessing;
    final buttonChild =
        _running
            ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(loadingLabel),
              ],
            )
            : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(widget.label),
              ],
            );

    final button =
        widget.filled
            ? FilledButton(
              onPressed: _running || !widget.enabled ? null : _handlePressed,
              style: buttonStyle,
              child: buttonChild,
            )
            : OutlinedButton(
              onPressed: _running || !widget.enabled ? null : _handlePressed,
              style: buttonStyle,
              child: buttonChild,
            );

    return MouseRegion(
      cursor:
          widget.enabled && !_running
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedScale(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            scale: widget.enabled && !_running && _hovered ? 1.015 : 1.0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: widget.enabled ? 1.0 : 0.68,
              child: SizedBox(height: 44, child: button),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 14,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: AppTypography.bodySmall,
                      height: 16 / 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class MovieAsyncActionRow extends StatefulWidget {
  const MovieAsyncActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
    this.loadingLabel,
    this.successMessage,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final String? loadingLabel;
  final String? successMessage;
  final Future<void> Function() onPressed;
  final bool enabled;

  @override
  State<MovieAsyncActionRow> createState() => _MovieAsyncActionRowState();
}

class _MovieAsyncActionRowState extends State<MovieAsyncActionRow> {
  bool _running = false;
  String? _errorMessage;
  bool _hovered = false;

  Future<void> _handlePressed() async {
    if (_running || !widget.enabled) {
      return;
    }
    setState(() {
      _running = true;
      _errorMessage = null;
    });
    try {
      await widget.onPressed();
      if (mounted && widget.successMessage != null) {
        showMovieFeedback(context, widget.successMessage!);
      }
    } catch (error) {
      final message = movieErrorMessage(error);
      if (mounted) {
        setState(() => _errorMessage = message);
        showMovieFeedback(context, message, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor:
          widget.enabled && !_running
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.videoColors.surfaceContainerHigh.withValues(
            alpha: _hovered ? 0.84 : 0.72,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                _hovered
                    ? context.videoColors.primary.withValues(alpha: 0.20)
                    : context.videoColors.outlineVariant.withValues(
                      alpha: 0.22,
                    ),
          ),
          boxShadow:
              _hovered
                  ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ]
                  : [],
        ),
        child: Row(
          children: [
            AnimatedScale(
              duration: Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              scale: _hovered ? 1.05 : 1.0,
              child: Icon(widget.icon, color: context.videoColors.primary),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.videoColors.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.videoColors.onSurfaceVariant,
                      fontSize: AppTypography.bodyMedium,
                      height: 18 / 13,
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 14,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontSize: AppTypography.bodySmall,
                              height: 16 / 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 12),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: _running || !widget.enabled ? null : _handlePressed,
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, 44),
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  foregroundColor: context.videoColors.onSurface,
                  side: BorderSide(
                    color: context.videoColors.outlineVariant.withValues(
                      alpha: 0.46,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child:
                    _running
                        ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.loadingLabel ??
                                  AppLocalizations.of(context).videoProcessing,
                            ),
                          ],
                        )
                        : Text(widget.actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
