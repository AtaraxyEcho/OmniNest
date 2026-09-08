import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';

class StreamNotice extends StatelessWidget {
  const StreamNotice({
    required this.videoCodec,
    required this.audioCodec,
    required this.container,
    required this.onDismiss,
    super.key,
  });

  final String? videoCodec;
  final String? audioCodec;
  final String? container;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final video = videoCodec?.toUpperCase() ?? l10n.videoUnknown;
    final audio = audioCodec?.toUpperCase() ?? l10n.videoUnknown;
    final cont = container?.toUpperCase() ?? l10n.videoUnknown;
    final reason = l10n.videoStatusSubtitle(cont, video, audio);
    return Positioned(
      top: 72,
      left: 16,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.6,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.videoColors.playerPanelSurface.withValues(
                alpha: 0.92,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    reason,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppTypography.bodyMedium,
                      height: 1.4,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.videoClose,
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
