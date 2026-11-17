import 'package:flutter/material.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/features/video/presentation/widgets/subtitle_parser.dart';

class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    required this.cues,
    required this.activeCueIndex,
    required this.controlsVisible,
    required this.isMobile,
    super.key,
  });

  final List<SubtitleCue> cues;
  final ValueNotifier<int> activeCueIndex;
  final bool controlsVisible;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration:
          MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      bottom:
          controlsVisible
              ? isMobile
                  ? 142
                  : 106
              : 28,
      left: 40,
      right: 40,
      child: IgnorePointer(
        child: ValueListenableBuilder<int>(
          valueListenable: activeCueIndex,
          builder: (context, index, _) {
            final hasCue = index >= 0 && index < cues.length;
            return Opacity(
              opacity: hasCue ? 1.0 : 0.0,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 960),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: context.videoColors.subtitleBg,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    hasCue ? cues[index].text : '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.videoColors.playerControlForeground,
                      fontSize: isMobile ? 18 : 21,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      shadows: const [
                        Shadow(
                          offset: Offset(1, 1),
                          blurRadius: 3,
                          color: Colors.black54,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
