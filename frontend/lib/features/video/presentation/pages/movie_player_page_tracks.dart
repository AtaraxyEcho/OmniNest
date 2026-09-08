part of 'movie_player_page.dart';

/// 播放器音轨与字幕轨道选择逻辑，自 _MoviePlayerPageState 拆分。
extension _MoviePlayerPageTracks on _MoviePlayerPageState {
  void _switchAudioMode(String mode) {
    if (_audioMode == mode) return;
    _updateState(() => _audioMode = mode);
    // 重新加载播放流
    _loadedUrl = null;
    final plan = _readPlaybackPlan();
    if (plan is AsyncData<PlaybackPlan>) {
      _openIfNeeded(plan.value);
    }
  }

  bool _hasAudioControls(PlaybackPlan plan) {
    return plan.hasAudioCache || _availableAudioTracks.isNotEmpty;
  }

  List<SubtitleTrack> _embeddedSubtitlesFor(PlaybackPlan plan) {
    final persistedIndexes =
        plan.subtitles
            .where((subtitle) => subtitle.isEmbedded)
            .map((subtitle) => subtitle.streamIndex.toString())
            .toSet();
    return _availableEmbeddedSubtitles
        .where((track) => !persistedIndexes.contains(track.id))
        .toList(growable: false);
  }

  void _selectAudioTrack(AudioTrack track) {
    _updateState(() => _activeAudioTrackId = track.id);
    _player.setAudioTrack(track);
  }

  // ── 画面比例 ──

  String get _currentRatioLabel {
    if (_isFill) return AppLocalizations.of(context).videoFillScreen;
    if (_aspectRatio == null) {
      return AppLocalizations.of(context).videoOriginalAspectRatio;
    }
    if ((_aspectRatio! - 16 / 9).abs() < 0.01) return '16:9';
    if ((_aspectRatio! - 21 / 9).abs() < 0.01) return '21:9';
    if ((_aspectRatio! - 4 / 3).abs() < 0.01) return '4:3';
    return AppLocalizations.of(context).videoOriginalAspectRatio;
  }

  void _openIfNeeded(PlaybackPlan plan) {
    _currentDurationSeconds = plan.durationSeconds;
    // 首次加载时根据缓存状态设置默认音频模式
    if (_loadedUrl == null && plan.hasAudioCache) {
      _audioMode = 'cached';
    } else if (_loadedUrl == null) {
      _audioMode = 'original';
    }
    // Web 端有 streamUrl 时使用转码流，否则使用原始 URL
    final playbackUrl = _resolvePlaybackUrl(plan);
    debugPrint(
      '[_openIfNeeded] mode=${plan.mode}, '
      'hasStreamUrl=${plan.streamUrl?.isNotEmpty == true}, '
      'audioMode=$_audioMode, '
      'isWeb=$isWebPlatform',
    );
    if (_loadedUrl == playbackUrl || playbackUrl.isEmpty) return;
    _loadedUrl = playbackUrl;
    final generation = ++_openGeneration;

    // 续播：未看完且有历史进度时从上次位置起播（已完成则从头）。
    final history =
        ref.read(movieItemHistoryProvider(widget.videoItemId)).asData?.value;
    final resumeSeconds =
        history == null || history.completed ? 0 : history.positionSeconds;

    // 取消上一次的 tracks 监听
    _tracksSub?.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _openGeneration) {
        return;
      }
      try {
        debugPrint('[_openIfNeeded] 正在打开播放器... resumeSeconds=$resumeSeconds');
        await _player.open(
          Media(
            playbackUrl,
            start: resumeSeconds > 0 ? Duration(seconds: resumeSeconds) : null,
          ),
          play: true,
        );
        if (!mounted || generation != _openGeneration) {
          return;
        }
        debugPrint('[_openIfNeeded] 播放器已打开');
        if (mounted && plan.hasAudioCache && isWebPlatform) {
          await _showAudioCacheNotice();
        }
      } catch (e) {
        debugPrint('[_openIfNeeded] 播放器打开失败: $e');
      }
      if (!mounted || generation != _openGeneration) {
        return;
      }
      await _player.setVolume(_volume);
      if (!mounted || generation != _openGeneration) {
        return;
      }

      // 监听缓冲状态
      _bufferingSub?.cancel();
      _bufferingSub = _player.stream.buffering.listen((buffering) {
        if (!mounted) return;
        if (buffering) {
          // 缓冲开始：记录当前播放状态
          _wasPlayingBeforeBuffering = _player.state.playing;
        } else if (_wasPlayingBeforeBuffering) {
          // 缓冲结束且之前正在播放：自动恢复播放
          _wasPlayingBeforeBuffering = false;
          _player.play();
        }
        _updateState(() => _isBuffering = buffering);
      });
      // 轮询缓冲进度 — 暂停时浏览器仍从 ffmpeg HTTP 流接收数据，
      // 但 _player.stream.buffer 不会触发事件，改用定时器轮询 _player.state.buffer
      _bufferPollTimer?.cancel();
      _bufferPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted) return;
        final buffer = _player.state.buffer;
        // fMP4 流的 duration 不可靠，优先使用播放计划的时长
        final durationMs =
            plan.durationSeconds > 0
                ? plan.durationSeconds * 1000
                : _player.state.duration.inMilliseconds;
        if (durationMs > 0) {
          final progress = (buffer.inMilliseconds / durationMs).clamp(0.0, 1.0);
          if ((progress - _bufferProgress).abs() > 0.001) {
            _updateState(() => _bufferProgress = progress);
          }
        }
      });
      // 轮询播放位置 — fMP4 流的 timeupdate 事件频率不足（仅在 fragment 边界触发），
      // 定时器保证进度条平滑更新
      _positionPollTimer?.cancel();
      _positionPollTimer = Timer.periodic(const Duration(milliseconds: 250), (
        _,
      ) {
        if (!mounted || _isSeeking) return;
        final pos = _player.state.position;
        if ((pos - _polledPosition.value).inMilliseconds.abs() > 200) {
          _polledPosition.value = pos;
        }
      });

      // 显式激活音频和字幕轨道
      _activateTracks();

      // 优先 seek 到用户拖拽目标（_seekStart），其次恢复上次播放进度
      if (_seekStart > 0) {
        await _player.seek(Duration(seconds: _seekStart));
        if (!mounted || generation != _openGeneration) {
          return;
        }
        _polledPosition.value = Duration(seconds: _seekStart);
        _updateState(() {
          _isSeeking = false;
        });
        _seekStart = 0;
      } else if (plan.positionSeconds > 0) {
        await _player.seek(Duration(seconds: plan.positionSeconds));
        if (!mounted || generation != _openGeneration) {
          return;
        }
      }
      await _syncCurrentProgress();
      if (!mounted || generation != _openGeneration) {
        return;
      }
      _startProgressSync(plan);
    });
  }

  /// 解析实际播放 URL：Web 端有 streamUrl 时优先使用服务端转码流
  String _resolvePlaybackUrl(PlaybackPlan plan) {
    return _playbackService.resolvePlaybackUrl(
      plan,
      useWebStream: isWebPlatform,
      audioMode: _audioMode,
      startSeconds: _seekStart,
    );
  }

  Future<void> _showAudioCacheNotice() async {
    if (!mounted || _audioNoticeChecked) return;
    _audioNoticeChecked = true;
    final noticeShown = await ref.read(
      videoLocalPreferencesControllerProvider.future,
    );
    if (!mounted) return;
    if (noticeShown) return;
    await ref
        .read(videoLocalPreferencesControllerProvider.notifier)
        .markAudioCacheNoticeShown();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).videoCompatibleAudioNotice,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2A2A36),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: AppLocalizations.of(context).videoGotIt,
          textColor: const Color(0xFFC3C0FF),
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  /// 显式选择音频和字幕轨道，确保解码器被激活。
  /// 先读取当前状态，再持续监听后续轨道变化。
  void _activateTracks() {
    _tracksSub?.cancel();
    final current = _player.state.tracks;
    _applyTracks(current);
    _tracksSub = _player.stream.tracks.listen(_applyTracks);
  }

  void _applyTracks(Tracks tracks) {
    if (isWebPlatform || !mounted) {
      return;
    }
    final audioTracks = tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList(growable: false);
    final subtitleTracks = tracks.subtitle
        .where(
          (track) =>
              track.id != 'auto' &&
              track.id != 'no' &&
              !track.uri &&
              !track.data,
        )
        .toList(growable: false);
    final changed =
        !_sameTrackIds(_availableAudioTracks, audioTracks) ||
        !_sameTrackIds(_availableEmbeddedSubtitles, subtitleTracks);
    if (changed) {
      _updateState(() {
        _availableAudioTracks = audioTracks;
        _availableEmbeddedSubtitles = subtitleTracks;
      });
    }
    if (_activeAudioTrackId == null && audioTracks.isNotEmpty) {
      final initialTrack = audioTracks.firstWhere(
        (track) => track.isDefault == true,
        orElse: () => audioTracks.first,
      );
      _activeAudioTrackId = initialTrack.id;
      _player.setAudioTrack(initialTrack);
    }
  }

  bool _sameTrackIds<T>(List<T> current, List<T> next) {
    if (current.length != next.length) {
      return false;
    }
    for (var index = 0; index < current.length; index++) {
      final currentId = switch (current[index]) {
        AudioTrack track => track.id,
        SubtitleTrack track => track.id,
        _ => '',
      };
      final nextId = switch (next[index]) {
        AudioTrack track => track.id,
        SubtitleTrack track => track.id,
        _ => '',
      };
      if (currentId != nextId) {
        return false;
      }
    }
    return true;
  }
}
