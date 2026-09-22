package com.omninest.modules.music.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.domain.MediaPlaybackProgress;
import com.omninest.modules.media.domain.MediaPlaybackType;
import com.omninest.modules.media.service.MediaPlaybackProgressService;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackPlanDto;
import com.omninest.modules.music.dto.MusicDtos.MusicPlaybackProgressDto;
import com.omninest.modules.music.dto.MusicDtos.PlaybackPositionDto;
import com.omninest.modules.music.dto.MusicDtos.SaveMusicPlaybackProgressRequest;
import com.omninest.modules.music.dto.OnlineMusicDtos.PlaybackUrlResult;
import com.omninest.modules.music.repository.MusicTrackRepository;
import com.omninest.modules.music.service.platform.MusicPlatform;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 音乐播放服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicPlaybackService {
    private final MusicTrackRepository trackRepository;
    private final FileQueryService fileQueryService;
    private final MusicPlatformService musicPlatformService;
    private final MusicPlaybackSessionService playbackSessionService;
    private final MediaPlaybackProgressService progressService;

    /**
     * 生成本地曲库播放计划。
     *
     * @param ownerUserId 用户 ID
     * @param trackId 曲目 ID
     * @return 播放计划
     */
    @Transactional(readOnly = true)
    public MusicPlaybackPlanDto playbackPlan(UUID ownerUserId, UUID trackId) {
        log.info("生成播放计划: trackId={}, userId={}", trackId, ownerUserId);
        MusicTrack track = trackRepository.findByIdAndOwnerUserId(trackId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "音乐资源不存在"));
        FileDownloadUrlDto downloadUrl = fileQueryService.createDownloadUrl(ownerUserId, track.getFileNodeId());
        return playbackSessionService.createLocalPlan(
                ownerUserId,
                track.getId(),
                downloadUrl.downloadUrl(),
                downloadUrl.expiresAt(),
                track.getDurationSeconds(),
                track.getFormat()
        );
    }

    /**
     * 生成在线平台曲目的播放计划。
     *
     * @param ownerUserId 用户 ID
     * @param platform 平台标识
     * @param songId 平台曲目 ID
     * @param mediaMid 媒体 ID
     * @param quality 音质
     * @return 播放计划
     */
    public MusicPlaybackPlanDto onlinePlaybackPlan(
            UUID ownerUserId,
            String platform,
            String songId,
            String mediaMid,
            String quality
    ) {
        PlaybackUrlResult result = musicPlatformService.getPlaybackUrl(
                ownerUserId,
                platform,
                songId,
                mediaMid,
                quality
        );
        if (result.url() == null || result.url().isBlank()) {
            String message = result.restriction() == null || result.restriction().isBlank()
                    ? "无法获取在线播放地址"
                    : result.restriction();
            throw new BusinessException(ErrorCode.BAD_REQUEST, message);
        }
        String sourcePlatform = MusicPlatform.fromApiValue(platform).apiValue();
        MusicPlaybackPlanDto plan = playbackSessionService.createOnlinePlan(
                ownerUserId,
                sourcePlatform,
                result.url(),
                null,
                result.format()
        );
        // 平台实际签发的音质档位随计划下发，供客户端音频参数胶囊展示。
        return new MusicPlaybackPlanDto(
                plan.trackId(),
                plan.url(),
                plan.expiresAt(),
                plan.durationSeconds(),
                plan.format(),
                result.quality()
        );
    }

    /**
     * 获取用户上次播放位置。
     *
     * @param ownerUserId 用户 ID
     * @return 播放位置
     */
    @Transactional(readOnly = true)
    public PlaybackPositionDto getLastPosition(UUID ownerUserId) {
        return progressService.latestByPrefix(ownerUserId, MediaPlaybackType.MUSIC, "local:")
                .map(progress -> new PlaybackPositionDto(
                        UUID.fromString(progress.getMediaKey().substring("local:".length())),
                        Math.toIntExact(progress.getPositionSeconds())
                ))
                .orElse(null);
    }

    /**
     * 保存播放位置。
     *
     * @param ownerUserId 用户 ID
     * @param trackId 曲目 ID
     * @param positionSeconds 播放位置秒数
     */
    @Transactional(rollbackFor = Exception.class)
    public void savePosition(UUID ownerUserId, UUID trackId, int positionSeconds) {
        log.info("保存播放位置: userId={}, trackId={}, positionSeconds={}", ownerUserId, trackId, positionSeconds);
        requireOwnedLocalTrack(ownerUserId, trackId);
        progressService.save(
                ownerUserId,
                MediaPlaybackType.MUSIC,
                "local:" + trackId,
                positionSeconds,
                0,
                false
        );
    }

    /**
     * 查询指定可播放对象的进度。
     *
     * @param ownerUserId 当前用户 ID
     * @param playableKey 类型化可播放键
     * @return 播放进度，不存在时返回空
     */
    @Transactional(readOnly = true)
    public MusicPlaybackProgressDto getProgress(UUID ownerUserId, String playableKey) {
        String normalized = validatePlayableKey(ownerUserId, playableKey);
        return progressService.find(ownerUserId, MediaPlaybackType.MUSIC, normalized)
                .map(this::toProgressDto)
                .orElse(null);
    }

    /**
     * 保存本地或在线音乐的统一播放进度。
     *
     * @param ownerUserId 当前用户 ID
     * @param request 进度请求
     * @return 保存后的进度
     */
    public MusicPlaybackProgressDto saveProgress(
            UUID ownerUserId,
            SaveMusicPlaybackProgressRequest request
    ) {
        String playableKey = validatePlayableKey(ownerUserId, request.playableKey());
        MediaPlaybackProgress progress = progressService.save(
                ownerUserId,
                MediaPlaybackType.MUSIC,
                playableKey,
                request.positionSeconds(),
                request.durationSeconds(),
                request.completed(),
                request.clientUpdatedAt(),
                request.deviceId()
        );
        return toProgressDto(progress);
    }

    private String validatePlayableKey(UUID ownerUserId, String playableKey) {
        String normalized = playableKey == null ? "" : playableKey.trim();
        if (normalized.startsWith("local:")) {
            UUID trackId;
            try {
                trackId = UUID.fromString(normalized.substring("local:".length()));
            } catch (IllegalArgumentException exception) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "本地音乐播放键格式不正确");
            }
            requireOwnedLocalTrack(ownerUserId, trackId);
            return "local:" + trackId;
        }
        if (normalized.startsWith("online:")) {
            String[] segments = normalized.split(":", 3);
            if (segments.length != 3 || segments[2].isBlank()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "在线音乐播放键格式不正确");
            }
            MusicPlatform platform = MusicPlatform.fromApiValue(segments[1]);
            return "online:" + platform.apiValue() + ":" + segments[2];
        }
        throw new BusinessException(ErrorCode.PARAM_ERROR, "音乐播放键格式不正确");
    }

    private void requireOwnedLocalTrack(UUID ownerUserId, UUID trackId) {
        if (trackRepository.findByIdAndOwnerUserId(trackId, ownerUserId).isEmpty()) {
            throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "音乐资源不存在");
        }
    }

    private MusicPlaybackProgressDto toProgressDto(MediaPlaybackProgress progress) {
        return new MusicPlaybackProgressDto(
                progress.getMediaKey(),
                progress.getPositionSeconds(),
                progress.getDurationSeconds(),
                progress.isCompleted(),
                progress.getUpdatedAt(),
                progress.getVersion()
        );
    }
}
