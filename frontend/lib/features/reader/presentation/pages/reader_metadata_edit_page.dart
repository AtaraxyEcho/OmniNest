import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/reader_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/widgets/app_error_view.dart';
import 'package:omninest/core/widgets/app_loading.dart';
import 'package:omninest/features/reader/application/reader_controller.dart';
import 'package:omninest/features/reader/application/reader_image_provider.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_cover_image.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_snack_bar.dart';

class ReaderMetadataEditPage extends ConsumerStatefulWidget {
  const ReaderMetadataEditPage({required this.itemId, super.key});

  final String itemId;

  @override
  ConsumerState<ReaderMetadataEditPage> createState() =>
      _ReaderMetadataEditPageState();
}

class _ReaderMetadataEditPageState
    extends ConsumerState<ReaderMetadataEditPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleCtrl;
  late TextEditingController _authorCtrl;
  late TextEditingController _descriptionCtrl;
  late TextEditingController _publisherCtrl;
  late TextEditingController _releaseDateCtrl;
  late TextEditingController _ratingCtrl;
  late TextEditingController _genresCtrl;
  late TextEditingController _isbnCtrl;
  String _serialStatus = 'UNKNOWN';
  bool _saving = false;

  static const _serialStatuses = ['UNKNOWN', 'ONGOING', 'COMPLETED'];

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/reader/items/${widget.itemId}');
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _authorCtrl = TextEditingController();
    _descriptionCtrl = TextEditingController();
    _publisherCtrl = TextEditingController();
    _releaseDateCtrl = TextEditingController();
    _ratingCtrl = TextEditingController();
    _genresCtrl = TextEditingController();
    _isbnCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _descriptionCtrl.dispose();
    _publisherCtrl.dispose();
    _releaseDateCtrl.dispose();
    _ratingCtrl.dispose();
    _genresCtrl.dispose();
    _isbnCtrl.dispose();
    super.dispose();
  }

  void _initForm(ReaderItemDetail detail) {
    final item = detail.item;
    if (_titleCtrl.text.isEmpty && item.title.isNotEmpty) {
      _titleCtrl.text = item.title;
    }
    if (_authorCtrl.text.isEmpty) {
      _authorCtrl.text = item.authorName ?? '';
    }
    if (_descriptionCtrl.text.isEmpty) {
      _descriptionCtrl.text = item.description ?? '';
    }
    if (_publisherCtrl.text.isEmpty) {
      _publisherCtrl.text = item.publisher ?? '';
    }
    if (_releaseDateCtrl.text.isEmpty) {
      _releaseDateCtrl.text =
          item.releaseDate?.toIso8601String().split('T').first ?? '';
    }
    if (_ratingCtrl.text.isEmpty) {
      _ratingCtrl.text = item.rating?.toString() ?? '';
    }
    if (_genresCtrl.text.isEmpty) {
      _genresCtrl.text = item.genres?.join(', ') ?? '';
    }
    if (_isbnCtrl.text.isEmpty) {
      _isbnCtrl.text = '';
    }
    if (_serialStatus == 'UNKNOWN' && item.serialStatus != null) {
      _serialStatus = item.serialStatus!;
    }
  }

  Map<String, dynamic> _buildUpdatePayload(ReaderItem original) {
    final fields = <String, dynamic>{};
    if (_titleCtrl.text.trim() != original.title) {
      fields['title'] = _titleCtrl.text.trim();
    }
    if (_authorCtrl.text.trim() != (original.authorName ?? '')) {
      fields['authorName'] = _authorCtrl.text.trim();
    }
    if (_descriptionCtrl.text.trim() != (original.description ?? '')) {
      fields['description'] = _descriptionCtrl.text.trim();
    }
    if (_publisherCtrl.text.trim() != (original.publisher ?? '')) {
      fields['publisher'] = _publisherCtrl.text.trim();
    }
    if (_releaseDateCtrl.text.trim() !=
        (original.releaseDate?.toIso8601String().split('T').first ?? '')) {
      fields['releaseDate'] = _releaseDateCtrl.text.trim();
    }
    final ratingText = _ratingCtrl.text.trim();
    final newRating = ratingText.isEmpty ? null : double.tryParse(ratingText);
    if (newRating != original.rating) {
      fields['rating'] = newRating;
    }
    final genresList =
        _genresCtrl.text
            .split(',')
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty)
            .toList();
    if (genresList.join(',') != (original.genres?.join(',') ?? '')) {
      fields['genres'] = genresList;
    }
    if (_serialStatus != (original.serialStatus ?? 'UNKNOWN')) {
      fields['serialStatus'] = _serialStatus;
    }
    final isbn = _isbnCtrl.text.trim();
    if (isbn.isNotEmpty) {
      fields['isbn'] = isbn;
    }
    return fields;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final detailAsync = ref.read(readerItemDetailProvider(widget.itemId));
    final detail = detailAsync.asData?.value;
    if (detail == null) return;

    final payload = _buildUpdatePayload(detail.item);
    if (payload.isEmpty) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showReaderSnackBar(context, l10n.readerNoChanges);
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(readerCenterControllerProvider.notifier)
          .updateItemMetadata(itemId: widget.itemId, fields: payload);
      if (!mounted) return;
      ref.invalidate(readerItemDetailProvider(widget.itemId));
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showReaderSnackBar(context, l10n.readerMetadataSaved);
      }
    } on Exception catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showReaderSnackBar(context, l10n.readerSaveFailed('$e'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(readerItemDetailProvider(widget.itemId));
    return Scaffold(
      backgroundColor: context.readerColors.surface,
      appBar: AppBar(
        backgroundColor: context.readerColors.surfaceContainer,
        leading: IconButton(
          tooltip: AppLocalizations.of(context).coreBack,
          icon: Icon(Icons.arrow_back_rounded),
          onPressed: _handleBack,
        ),
        title: Text(
          AppLocalizations.of(context).readerEditMetadata,
          style: TextStyle(
            color: context.readerColors.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child:
                  _saving
                      ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                      : Text(AppLocalizations.of(context).readerSave),
            ),
          ),
        ],
      ),
      body: detailAsync.when(
        data: (detail) {
          _initForm(detail);
          return _buildForm(detail);
        },
        error: (e, _) => AppErrorView(message: e.toString()),
        loading: () => const AppLoading.detail(),
      ),
    );
  }

  Widget _buildForm(ReaderItemDetail detail) {
    final l10n = AppLocalizations.of(context);
    final item = detail.item;
    return Form(
      key: _formKey,
      onChanged: () {},
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCoverSection(item),
                const SizedBox(height: 32),
                _buildTextField(
                  controller: _titleCtrl,
                  label: l10n.readerLabelTitle,
                  required: true,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _authorCtrl,
                  label: l10n.readerLabelAuthor,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _descriptionCtrl,
                  label: l10n.readerLabelDescription,
                  maxLines: 5,
                ),
                const SizedBox(height: 16),
                _buildFieldPair(
                  first: _buildTextField(
                    controller: _publisherCtrl,
                    label: l10n.readerLabelPublisher,
                  ),
                  second: _buildTextField(
                    controller: _releaseDateCtrl,
                    label: l10n.readerLabelReleaseDate,
                  ),
                ),
                const SizedBox(height: 16),
                _buildFieldPair(
                  first: _buildTextField(
                    controller: _ratingCtrl,
                    label: l10n.readerLabelRating,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  second: _buildSerialStatusDropdown(),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _genresCtrl,
                  label: l10n.readerLabelGenres,
                ),
                const SizedBox(height: 16),
                _buildTextField(controller: _isbnCtrl, label: 'ISBN'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverSection(ReaderItem item) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        children: [
          Container(
            width: 160,
            height: 224,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: context.readerColors.surfaceContainerHighest,
              border: Border.all(
                color: context.readerColors.outlineVariant.withValues(
                  alpha: 0.3,
                ),
              ),
            ),
            child:
                item.hasCover
                    ? AuthCoverImage(
                      itemId: item.id,
                      fit: BoxFit.cover,
                      fallback: _coverPlaceholder(),
                    )
                    : _coverPlaceholder(),
          ),
          SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickFromFiles(),
                icon: Icon(Icons.folder_open_rounded, size: 18),
                label: Text(l10n.readerSelectFromFile),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.readerColors.onSurface,
                  side: BorderSide(
                    color: context.readerColors.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _pickAndUpload(),
                icon: Icon(Icons.upload_rounded, size: 18),
                label: Text(l10n.readerUploadCover),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.readerColors.onSurface,
                  side: BorderSide(
                    color: context.readerColors.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _coverPlaceholder() {
    return Center(
      child: Icon(
        Icons.image_outlined,
        size: 48,
        color: context.readerColors.onSurfaceVariant.withValues(alpha: 0.4),
      ),
    );
  }

  /// 双列表单字段组：窄屏（可用宽 <420 或大字号）改纵向堆叠，
  /// 判定阈值对齐漫画详情页先例。
  Widget _buildFieldPair({required Widget first, required Widget second}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow =
            constraints.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 16), second],
          );
        }
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 16),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(
        color: context.readerColors.onSurface,
        fontSize: AppTypography.bodyLarge,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: context.readerColors.onSurfaceVariant.withValues(alpha: 0.8),
          fontSize: AppTypography.bodyMedium,
        ),
        filled: true,
        fillColor: context.readerColors.surfaceContainerHigh.withValues(
          alpha: 0.5,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: context.readerColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: context.readerColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      validator:
          required
              ? (v) =>
                  (v == null || v.trim().isEmpty)
                      ? AppLocalizations.of(context).readerFieldRequired(label)
                      : null
              : null,
    );
  }

  Widget _buildSerialStatusDropdown() {
    final l10n = AppLocalizations.of(context);
    return AppDropdown<String>(
      value: _serialStatus,
      label: l10n.readerLabelSerialStatus,
      items: [
        for (final s in _serialStatuses)
          AppDropdownItem(
            value: s,
            label: switch (s) {
              'ONGOING' => l10n.readerStatusOngoing,
              'COMPLETED' => l10n.readerStatusCompleted,
              _ => l10n.readerStatusUnknown,
            },
          ),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _serialStatus = v);
      },
    );
  }

  Future<void> _pickFromFiles() async {
    // 弹出文件选择对话框，列出托管存储中的图片文件。
    try {
      final candidates =
          await ref
              .read(readerCenterControllerProvider.notifier)
              .importCandidates();
      if (!mounted) {
        return;
      }
      final imageFiles =
          candidates.where((candidate) {
            final name = candidate.fileName.toLowerCase();
            return name.endsWith('.jpg') ||
                name.endsWith('.jpeg') ||
                name.endsWith('.png') ||
                name.endsWith('.webp');
          }).toList();
      if (!mounted || imageFiles.isEmpty) {
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          showReaderSnackBar(context, l10n.readerNoImageFiles);
        }
        return;
      }
      final selected = await showDialog<ReaderImportCandidate>(
        context: context,
        builder:
            (ctx) => _FilePickerDialog(
              files: imageFiles,
              title: AppLocalizations.of(context).readerSelectCoverImage,
            ),
      );
      if (selected == null || !mounted) return;
      final fileNodeId = selected.fileNodeId;
      if (fileNodeId.isEmpty) return;
      await ref
          .read(readerCenterControllerProvider.notifier)
          .setCoverFromFile(itemId: widget.itemId, fileNodeId: fileNodeId);
      if (!mounted) {
        return;
      }
      // 新封面上传后旧字节缓存必须同步失效，否则 LRU 会继续命中旧图。
      ReaderCoverByteCache.remove(widget.itemId);
      ref.invalidate(coverBytesProvider(widget.itemId));
      ref.invalidate(readerItemDetailProvider(widget.itemId));
      final l10n = AppLocalizations.of(context);
      showReaderSnackBar(context, l10n.readerCoverUpdated);
    } on Exception catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showReaderSnackBar(context, l10n.readerOperationFailedError('$e'));
      }
    }
  }

  Future<void> _pickAndUpload() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      if (!mounted) {
        return;
      }
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;
      await ref
          .read(readerCenterControllerProvider.notifier)
          .uploadCover(
            itemId: widget.itemId,
            imageBytes: Uint8List.fromList(bytes),
            fileName: file.name,
          );
      if (!mounted) {
        return;
      }
      // 新封面上传后旧字节缓存必须同步失效，否则 LRU 会继续命中旧图。
      ReaderCoverByteCache.remove(widget.itemId);
      ref.invalidate(coverBytesProvider(widget.itemId));
      ref.invalidate(readerItemDetailProvider(widget.itemId));
      final l10n = AppLocalizations.of(context);
      showReaderSnackBar(context, l10n.readerCoverUploaded);
    } on Exception catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showReaderSnackBar(context, l10n.readerUploadFailed('$e'));
      }
    }
  }
}

class _FilePickerDialog extends StatelessWidget {
  const _FilePickerDialog({required this.files, required this.title});

  final List<ReaderImportCandidate> files;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.readerColors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.readerColors.onSurface,
                      fontSize: AppTypography.titleMedium,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: AppLocalizations.of(context).coreClose,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(vertical: 8),
                itemCount: files.length,
                itemBuilder: (ctx, index) {
                  final file = files[index];
                  final name =
                      file.fileName.isEmpty
                          ? AppLocalizations.of(context).readerUnknownFile
                          : file.fileName;
                  return ListTile(
                    leading: Icon(
                      Icons.image_outlined,
                      color: context.readerColors.onSurfaceVariant,
                    ),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.readerColors.onSurface,
                        fontSize: AppTypography.bodyLarge,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, file),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
