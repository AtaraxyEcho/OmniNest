package com.omninest.modules.video.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.video.domain.MediaSubtitleTrack;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.dto.MovieDtos.SubtitleTrackDto;
import com.omninest.modules.video.dto.MovieDtos.SubtitleUpdateRequest;
import com.omninest.modules.video.dto.MovieDtos.SubtitleUploadRequest;
import com.omninest.modules.video.repository.MediaSubtitleTrackRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class SubtitleManagementService {

    private static final Set<String> SUBTITLE_EXTENSIONS = Set.of(
            "srt", "vtt", "ass", "ssa", "sub", "ttml"
    );

    private final MediaProcessingLimitsProperties processingLimits;
    private final MediaSubtitleTrackRepository subtitleTrackRepository;
    private final MediaVideoItemRepository videoItemRepository;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final FileQueryService fileQueryService;
    private final MediaContentAccessService mediaContentAccessService;
    private final MediaPlaybackTokenService mediaPlaybackTokenService;
    private final MediaSyncEventService syncEventService;

    @Transactional(readOnly = true)
    public List<SubtitleTrackDto> list(UUID ownerUserId, UUID videoItemId) {
        MediaVideoItem item = mediaContentAccessService.requireReadableVideo(ownerUserId, videoItemId);
        MediaPlaybackTokenService.IssuedMediaToken token = mediaPlaybackTokenService.issue(ownerUserId, videoItemId);
        return subtitleTrackRepository
                .findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(item.getOwnerUserId(), videoItemId)
                .stream()
                .map(track -> toReadDto(videoItemId, token.token(), track))
                .toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public SubtitleTrackDto upload(UUID ownerUserId, UUID videoItemId, SubtitleUploadRequest request) {
        findVideoItem(ownerUserId, videoItemId);
        validateSubtitleFile(ownerUserId, request.fileNodeId());

        List<MediaSubtitleTrack> existing = subtitleTrackRepository
                .findByOwnerUserIdAndVideoItemIdOrderBySortOrderAsc(ownerUserId, videoItemId);
        int maxOrder = existing.stream()
                .mapToInt(MediaSubtitleTrack::getSortOrder)
                .max()
                .orElse(0);

        MediaSubtitleTrack track = new MediaSubtitleTrack();
        track.setId(UUID.randomUUID());
        track.setOwnerUserId(ownerUserId);
        track.setVideoItemId(videoItemId);
        track.setFileNodeId(request.fileNodeId());
        track.setLanguage(request.language() != null ? request.language() : "und");
        track.setLabel(request.label() != null ? request.label() : "字幕");
        track.setTrackKind(request.kind() != null ? request.kind() : "SUBTITLE");
        track.setSortOrder(maxOrder + 1);
        subtitleTrackRepository.save(track);
        recordSubtitleEvent(ownerUserId, videoItemId);
        return toDto(ownerUserId, track);
    }

    @Transactional(rollbackFor = Exception.class)
    public SubtitleTrackDto update(UUID ownerUserId, UUID subtitleId, SubtitleUpdateRequest request) {
        MediaSubtitleTrack track = findTrack(ownerUserId, subtitleId);
        if (request.language() != null) {
            track.setLanguage(request.language());
        }
        if (request.label() != null) {
            track.setLabel(request.label());
        }
        if (request.kind() != null) {
            track.setTrackKind(request.kind());
        }
        subtitleTrackRepository.save(track);
        recordSubtitleEvent(ownerUserId, track.getVideoItemId());
        return toDto(ownerUserId, track);
    }

    @Transactional(rollbackFor = Exception.class)
    public void delete(UUID ownerUserId, UUID subtitleId) {
        MediaSubtitleTrack track = findTrack(ownerUserId, subtitleId);
        subtitleTrackRepository.delete(track);
        recordSubtitleEvent(ownerUserId, track.getVideoItemId());
    }

    /** 字幕轨道增删改后按所属影片发出 VIDEO 作用域失效事件，resourceId 固定为影片 ID。 */
    private void recordSubtitleEvent(UUID ownerUserId, UUID videoItemId) {
        syncEventService.record(
                ownerUserId,
                SyncScope.VIDEO,
                "VIDEO_ITEM",
                videoItemId == null ? null : videoItemId.toString(),
                SyncAction.UPDATED,
                null,
                Map.of()
        );
    }

    private MediaSubtitleTrack findTrack(UUID ownerUserId, UUID subtitleId) {
        MediaSubtitleTrack track = subtitleTrackRepository.findById(subtitleId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "字幕轨道不存在"));
        if (!track.getOwnerUserId().equals(ownerUserId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "无权操作此字幕轨道");
        }
        return track;
    }

    private MediaVideoItem findVideoItem(UUID ownerUserId, UUID videoItemId) {
        return videoItemRepository.findByIdAndOwnerUserId(videoItemId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在"));
    }

    private void validateSubtitleFile(UUID ownerUserId, UUID fileNodeId) {
        FileDescriptor file = fileLifecycleGuard.requireOwnedWritable(ownerUserId, fileNodeId);
        if (!"FILE".equals(file.nodeType())) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "字幕来源必须是文件");
        }
        if (file.sizeBytes() <= 0 || file.sizeBytes() > processingLimits.getMaxSubtitleBytes()) {
            throw new BusinessException(ErrorCode.FILE_SIZE_EXCEEDED, "字幕文件大小不能超过 10MB");
        }
        String fileName = file.name() == null ? "" : file.name();
        int extensionIndex = fileName.lastIndexOf('.');
        String extension = extensionIndex < 0
                ? ""
                : fileName.substring(extensionIndex + 1).toLowerCase(Locale.ROOT);
        if (!SUBTITLE_EXTENSIONS.contains(extension)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "字幕文件格式不受支持");
        }
        String mimeType = file.mimeType() == null ? "" : file.mimeType().toLowerCase(Locale.ROOT);
        if (!mimeType.isBlank()
                && !mimeType.startsWith("text/")
                && !"application/octet-stream".equals(mimeType)
                && !"application/x-subrip".equals(mimeType)
                && !"application/ttml+xml".equals(mimeType)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "字幕文件内容类型不受支持");
        }
    }

    private SubtitleTrackDto toDto(UUID ownerUserId, MediaSubtitleTrack track) {
        String url = null;
        if (track.getFileNodeId() != null) {
            url = fileQueryService.createDownloadUrl(ownerUserId, track.getFileNodeId()).downloadUrl();
        }
        boolean embedded = track.getFileNodeId() == null;
        return new SubtitleTrackDto(
                track.getId(),
                track.getLanguage(),
                track.getLabel(),
                track.getTrackKind(),
                url,
                embedded,
                track.getStreamIndex(),
                track.getCreatedAt()
        );
    }

    private SubtitleTrackDto toReadDto(UUID videoItemId, String token, MediaSubtitleTrack track) {
        boolean embedded = track.getFileNodeId() == null;
        String url = "/api/v1/public/video/items/" + videoItemId
                + "/subtitles/" + track.getId() + "?token=" + token;
        return new SubtitleTrackDto(
                track.getId(),
                track.getLanguage(),
                track.getLabel(),
                track.getTrackKind(),
                url,
                embedded,
                track.getStreamIndex(),
                track.getCreatedAt()
        );
    }
}
