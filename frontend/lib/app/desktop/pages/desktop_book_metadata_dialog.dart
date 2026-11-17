import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        FilteringTextInputFormatter,
        LengthLimitingTextInputFormatter,
        TextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:omninest/app/desktop/desktop_icons.dart';
import 'package:omninest/app/desktop/desktop_toast.dart';
import 'package:omninest/app/desktop/widgets/desktop_controls.dart';
import 'package:omninest/app/desktop/widgets/desktop_cover.dart';
import 'package:omninest/app/desktop/widgets/desktop_dialogs.dart';
import 'package:omninest/app/desktop/widgets/desktop_fields.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';

/// 书籍元数据编辑：样例 `Reader.tsx` 的 `MetaDialog`，由右侧抽屉承载。
class DesktopBookMetadataDrawer extends ConsumerStatefulWidget {
  const DesktopBookMetadataDrawer({required this.item, super.key});

  final ReaderItem item;

  @override
  ConsumerState<DesktopBookMetadataDrawer> createState() =>
      _DesktopBookMetadataDrawerState();
}

class _DesktopBookMetadataDrawerState
    extends ConsumerState<DesktopBookMetadataDrawer> {
  late final TextEditingController _title = TextEditingController(
    text: widget.item.title,
  );
  late final TextEditingController _author = TextEditingController(
    text: widget.item.authorName ?? '',
  );
  late final TextEditingController _tags = TextEditingController(
    text: widget.item.genres?.join(', ') ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.item.description ?? '',
  );
  late final TextEditingController _series = TextEditingController(
    text: widget.item.seriesName ?? '',
  );
  late final TextEditingController _volume = TextEditingController(
    text: widget.item.volumeNumber?.toString() ?? '',
  );
  late final TextEditingController _coverImageUrl = TextEditingController(
    text: widget.item.coverImageUrl ?? '',
  );
  late String _readerType = widget.item.readerType;
  bool _saving = false;

  static const _readerTypes = ['BOOK', 'COMIC', 'MANGA'];

  @override
  void initState() {
    super.initState();
    // 书名必填：样例 `MetaEditor` 的 `disabled={bad}` 与 `.sf.bad` 都随输入
    // 实时变，所以这里监听主字段重算一次。
    _title.addListener(_onFormChanged);
    _volume.addListener(_onFormChanged);
  }

  void _onFormChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 样例 `bad = !v.title.trim() || …`：书籍元数据只有书名是硬约束。
  bool get _bad => _title.text.trim().isEmpty || !_volumeIsValid;

  bool get _volumeIsValid {
    final value = _volume.text.trim();
    if (value.isEmpty) return true;
    final parsed = int.tryParse(value);
    return parsed != null && parsed >= 1 && parsed <= 999;
  }

  @override
  void dispose() {
    _title
      ..removeListener(_onFormChanged)
      ..dispose();
    _volume
      ..removeListener(_onFormChanged)
      ..dispose();
    _author.dispose();
    _tags.dispose();
    _description.dispose();
    _series.dispose();
    _coverImageUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DesktopDrawerFrame(
      eyebrow: l10n.desktopBookDetails,
      title: l10n.desktopBookEditMetadata,
      footer: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.item.hasManualMetadataOverride) ...[
            DesktopButton(
              label: l10n.desktopBookRestoreOriginal,
              variant: DesktopButtonVariant.ghost,
              onPressed: _saving ? null : _restoreOriginal,
            ),
            const SizedBox(width: 10),
          ],
          DesktopButton(
            label: l10n.adminCancel,
            variant: DesktopButtonVariant.ghost,
            onPressed: _saving ? null : () => closeDesktopModal(context, false),
          ),
          const SizedBox(width: 10),
          DesktopButton(
            label: l10n.adminSave,
            variant: DesktopButtonVariant.primary,
            busy: _saving,
            onPressed: _saving || _bad ? null : _save,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                height: 102,
                child: DesktopCover(
                  url: widget.item.coverUrl,
                  kind: DesktopCoverKind.reader,
                  readerItemId: widget.item.id,
                  fallbackIcon: DesktopIcons.book,
                  borderRadius: BorderRadius.circular(
                    DesktopMetrics.radiusSmall,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _field(
                      l10n.desktopBookTitle,
                      _title,
                      required: true,
                      error:
                          _title.text.trim().isEmpty
                              ? l10n.desktopBookTitleRequired
                              : null,
                    ),
                    _field(l10n.desktopBookAuthor, _author),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text(l10n.desktopBookType),
                const SizedBox(width: 12),
                Expanded(
                  child: DesktopSeg<String>(
                    options: _readerTypes,
                    value: _readerType,
                    labelOf:
                        (type) => switch (type) {
                          'COMIC' => l10n.desktopBookTypeComic,
                          'MANGA' => l10n.desktopBookTypeManga,
                          _ => l10n.desktopBookTypeBook,
                        },
                    onChanged: (value) => setState(() => _readerType = value),
                    small: true,
                  ),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _field(l10n.desktopBookSeries, _series)),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  l10n.desktopBookVolume,
                  _volume,
                  hint: l10n.desktopBookVolumeHint,
                  error: _volumeIsValid ? null : l10n.desktopBookVolumeInvalid,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DesktopTextField(
              controller: _tags,
              label: l10n.desktopBookTags,
              hint: l10n.desktopBookTagsHint,
              height: 36,
            ),
          ),
          const SizedBox(height: 2),
          DesktopTextField(
            controller: _description,
            label: l10n.desktopBookDescription,
            height: 120,
            maxLines: 5,
            counterBuilder: (text) => l10n.desktopFieldChars(text.length),
          ),
          const SizedBox(height: 12),
          DesktopTextField(
            controller: _coverImageUrl,
            label: l10n.desktopBookCoverUrl,
            hint: l10n.desktopBookCoverUrlHint,
            height: 36,
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool required = false,
    String? error,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DesktopTextField(
        controller: controller,
        label: label,
        required: required,
        error: error,
        hint: hint,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        height: 36,
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .updateItemMetadata(
            itemId: widget.item.id,
            fields: {
              'title': _title.text.trim(),
              'authorName': _author.text.trim(),
              'genres':
                  _tags.text
                      .split(',')
                      .map((tag) => tag.trim())
                      .where((tag) => tag.isNotEmpty)
                      .toList(),
              'description': _description.text.trim(),
              if (_readerType != widget.item.readerType)
                'readerType': _readerType,
              if (_series.text.trim() != (widget.item.seriesName ?? ''))
                'seriesName': _series.text.trim(),
              if (_volume.text.trim().isEmpty &&
                  widget.item.volumeNumber != null)
                'clearVolumeNumber': true,
              if (_volume.text.trim().isNotEmpty &&
                  int.tryParse(_volume.text.trim()) != widget.item.volumeNumber)
                'volumeNumber': int.parse(_volume.text.trim()),
              if (_coverImageUrl.text.trim() !=
                  (widget.item.coverImageUrl ?? ''))
                'coverImageUrl': _coverImageUrl.text.trim(),
            },
          );
      if (!mounted) {
        return;
      }
      // 样例 `MetaEditor.tsx:19`：保存成功先回一条 `Metadata saved` 提示，
      // 再关抽屉——抽屉一关，用户就没别的线索了。
      showDesktopToast(
        context,
        l10n.desktopBookMetadataSaved,
        icon: DesktopIcons.check,
      );
      closeDesktopModal(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showOmniFeedback(
          context,
          errorReason(error, l10n),
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }

  Future<void> _restoreOriginal() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .updateItemMetadata(
            itemId: widget.item.id,
            fields: const {'restoreOriginal': true},
          );
      if (!mounted) return;
      showDesktopToast(
        context,
        l10n.desktopBookMetadataRestored,
        icon: DesktopIcons.check,
      );
      closeDesktopModal(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showOmniFeedback(
          context,
          errorReason(error, l10n),
          severity: OmniFeedbackSeverity.error,
        );
      }
    }
  }
}
