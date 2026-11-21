part of 'movie_player_page.dart';

/// 播放页的字幕选择、导入与外挂 VTT 渲染（与页面 state 共用同一批字段）。
extension _MoviePlayerSubtitles on _MoviePlayerPageState {
  void _selectSubtitle(PlaybackSubtitle sub) {
    final generation = ++_subtitleGeneration;
    _updateState(() => _activeSubtitleId = sub.id.hashCode);
    if (isWebPlatform) {
      // Web 端：media_kit 的 SubtitleTrack 在 MSE 模式下不生效，
      // 改用自定义 WebVTT 覆盖层。
      // 内嵌字幕已在探测时提取为 WebVTT 存储到 MinIO，url 为 presigned URL。
      if (sub.url != null && sub.url!.isNotEmpty) {
        _fetchAndDisplayWebVTT(sub.url!, generation);
      }
    } else if (sub.isEmbedded) {
      // Desktop/Android：内嵌字幕按 stream index 选择（libmpv 原生支持）
      unawaited(
        _player.setSubtitleTrack(
          SubtitleTrack('${sub.streamIndex}', sub.label, sub.language),
        ),
      );
    } else if (sub.isExternal) {
      // Desktop/Android 外挂字幕
      unawaited(
        _player.setSubtitleTrack(
          SubtitleTrack.uri(sub.url!, title: sub.label, language: sub.language),
        ),
      );
    } else {
      unawaited(_player.setSubtitleTrack(SubtitleTrack.auto()));
    }
  }

  void _selectEmbeddedSubtitle(SubtitleTrack track) {
    final generation = ++_subtitleGeneration;
    _updateState(() => _activeSubtitleId = track.id.hashCode);
    if (track.data) {
      final cues = parseSubtitleContent(track.id);
      if (isWebPlatform) {
        _displaySubtitleCues(cues, generation);
      } else {
        unawaited(_player.setSubtitleTrack(track));
      }
      return;
    }
    if (!isWebPlatform) {
      unawaited(_player.setSubtitleTrack(track));
    }
  }

  Future<void> _importSubtitle() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await FilePick.pickFiles(
        allowedExtensions: const ['srt', 'ass', 'ssa', 'vtt'],
      );
      if (result.isEmpty || !mounted) {
        return;
      }
      final file = result.first;
      final fileSize = file.lengthSync() ?? await file.length() ?? 0;
      if (!mounted) {
        return;
      }
      if (fileSize > maxLocalSubtitleBytes) {
        showMovieFeedback(
          context,
          l10n.videoSubtitleFileTooLarge,
          isError: true,
        );
        return;
      }
      final bytes = await file.readBytes();
      if (!mounted) {
        return;
      }
      if (bytes.isEmpty) {
        showMovieFeedback(
          context,
          l10n.videoSubtitleImportFailed,
          isError: true,
        );
        return;
      }
      final content = decodeTextFileBytes(bytes);
      // 整集 ASS 可能上万条 cue，放后台 isolate 解析，别让导入卡住播放画面。
      final cues = await parseSubtitleContentAsync(content);
      if (!mounted) {
        return;
      }
      if (cues.isEmpty) {
        showMovieFeedback(context, l10n.videoSubtitleNoCues, isError: true);
        return;
      }
      final track = SubtitleTrack.data(
        content,
        title: file.name,
        language: inferSubtitleLanguage(file.name),
      );
      if (!mounted) {
        return;
      }
      final generation = ++_subtitleGeneration;
      _updateState(() {
        _importedSubtitle = track;
        _activeSubtitleId = track.id.hashCode;
      });
      if (isWebPlatform) {
        _displaySubtitleCues(cues, generation);
      } else {
        await _player.setSubtitleTrack(track);
      }
      if (mounted) {
        showMovieFeedback(context, l10n.videoSubtitleImportSuccess);
      }
    } on Object catch (error) {
      if (mounted) {
        showMovieFeedback(
          context,
          failureToast(l10n, l10n.videoSubtitleImportFailed, error),
          isError: true,
        );
      }
    }
  }

  void _disableSubtitle() {
    _subtitleGeneration++;
    _updateState(() {
      _activeSubtitleId = null;
      _subtitleCues = [];
    });
    _activeCueIndex.value = -1;
    _subtitlePositionSub?.cancel();
    _subtitlePositionSub = null;
    if (!isWebPlatform) {
      unawaited(_player.setSubtitleTrack(SubtitleTrack.no()));
    }
  }

  /// 获取 WebVTT 字幕并以自定义覆盖层显示（Web 端专用）
  Future<void> _fetchAndDisplayWebVTT(String url, int generation) async {
    try {
      final subtitleContent = await _playbackService.loadSubtitle(url);
      if (!mounted || generation != _subtitleGeneration) return;
      devLog('字幕内容长度: ${subtitleContent.length}');
      final cues = await parseSubtitleContentAsync(subtitleContent);
      devLog('字幕解析完成: ${cues.length} 条字幕');
      if (!mounted || generation != _subtitleGeneration) return;
      _displaySubtitleCues(cues, generation);
    } catch (error) {
      devLog('WebVTT 获取失败: $error');
      if (!mounted || generation != _subtitleGeneration) return;
      _disableSubtitle();
      showMovieFeedback(
        context,
        AppLocalizations.of(context).videoSubtitleDisplayFailed,
        isError: true,
      );
    }
  }

  void _displaySubtitleCues(List<SubtitleCue> cues, int generation) {
    if (!mounted || generation != _subtitleGeneration) return;
    _subtitlePositionSub?.cancel();
    _updateState(() => _subtitleCues = cues);
    _activeCueIndex.value = -1;
    var lastIndex = -1;
    _subtitlePositionSub = _player.stream.position.listen((position) {
      if (!mounted || _subtitleCues.isEmpty) return;
      final newIndex = findActiveSubtitleCueIndex(_subtitleCues, position);
      if (newIndex != lastIndex) {
        lastIndex = newIndex;
        _activeCueIndex.value = newIndex;
      }
    });
  }

  void _toggleSubtitle(PlaybackPlan plan) {
    if (_activeSubtitleId != null) {
      _disableSubtitle();
    } else if (plan.subtitles.isNotEmpty) {
      _selectSubtitle(plan.subtitles.first);
    } else if (_availableEmbeddedSubtitles.isNotEmpty) {
      _selectEmbeddedSubtitle(_availableEmbeddedSubtitles.first);
    } else if (_importedSubtitle case final imported?) {
      _selectEmbeddedSubtitle(imported);
    }
  }
}
