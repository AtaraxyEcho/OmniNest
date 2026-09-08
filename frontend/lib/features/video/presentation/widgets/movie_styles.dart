import 'package:flutter/material.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:omninest/features/video/presentation/widgets/movie_feedback.dart';

ButtonStyle movieFilledButtonStyle(BuildContext context) {
  final c = context.videoColors;
  return FilledButton.styleFrom(
    minimumSize: const Size(0, 44),
    padding: const EdgeInsets.symmetric(horizontal: 18),
    backgroundColor: c.primaryContainer,
    foregroundColor: c.onPrimaryContainer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: const TextStyle(
      fontSize: AppTypography.bodyMedium,
      fontWeight: FontWeight.w800,
    ),
  );
}

ButtonStyle movieOutlinedButtonStyle(BuildContext context) {
  final c = context.videoColors;
  return OutlinedButton.styleFrom(
    minimumSize: const Size(0, 44),
    padding: const EdgeInsets.symmetric(horizontal: 18),
    foregroundColor: c.onSurface,
    side: BorderSide(color: c.outlineVariant.withValues(alpha: 0.46)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: const TextStyle(
      fontSize: AppTypography.bodyMedium,
      fontWeight: FontWeight.w800,
    ),
  );
}

InputDecoration movieInputDecoration(BuildContext context, String label) {
  final c = context.videoColors;
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: c.onSurfaceVariant),
    filled: true,
    fillColor: c.surfaceContainerHigh.withValues(alpha: 0.44),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.outlineVariant.withValues(alpha: 0.24)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.outlineVariant.withValues(alpha: 0.24)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: c.primary),
    ),
  );
}

void showMovieMessage(BuildContext context, String message) {
  showMovieFeedback(context, message);
}

Future<void> runMovieAction(
  BuildContext context,
  Future<void> Function() action,
  String successMessage,
) async {
  try {
    await action();
    if (context.mounted) {
      showMovieFeedback(context, successMessage);
    }
  } catch (error) {
    if (context.mounted) {
      showMovieFeedback(context, movieErrorMessage(error), isError: true);
    }
  }
}
