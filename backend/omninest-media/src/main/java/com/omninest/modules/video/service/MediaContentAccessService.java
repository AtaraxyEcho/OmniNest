package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.MediaContentPurpose;
import com.omninest.modules.file.dto.FileContentResource;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.FileContentAccessService;
import com.omninest.modules.media.domain.ResourceType;
import com.omninest.modules.video.domain.ContentAsset;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.repository.ContentAssetRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.util.Locale;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 将媒体业务授权和 File Provider 安全读取连接为受控内容边界。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MediaContentAccessService {

    private final MediaVideoItemRepository videoItemRepository;
    private final MediaTvSeriesRepository tvSeriesRepository;
    private final MediaLibraryAccessService libraryAccessService;
    private final FileContentAccessService fileContentAccessService;
    private final MediaPlaybackTokenService tokenService;
    private final ContentAssetRepository contentAssetRepository;

    /** 校验请求用户并返回可读视频。 */
    @Transactional(readOnly = true)
    public MediaVideoItem requireReadableVideo(UUID requesterUserId, UUID videoItemId) {
        MediaVideoItem item = videoItemRepository.findById(videoItemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在"));
        if (item.getLibrarySourceId() == null) {
            libraryAccessService.requireReadPermission(requesterUserId);
            if (!item.getOwnerUserId().equals(requesterUserId)) {
                throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在");
            }
            return item;
        }
        libraryAccessService.requireRead(requesterUserId, item.getLibrarySourceId());
        return item;
    }

    /** 校验请求用户并返回可读系列。 */
    @Transactional(readOnly = true)
    public MediaTvSeries requireReadableSeries(UUID requesterUserId, UUID seriesId) {
        MediaTvSeries series = tvSeriesRepository.findById(seriesId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "剧集不存在"));
        if (series.getLibrarySourceId() == null) {
            libraryAccessService.requireReadPermission(requesterUserId);
            if (!series.getOwnerUserId().equals(requesterUserId)) {
                throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "剧集不存在");
            }
            return series;
        }
        libraryAccessService.requireRead(requesterUserId, series.getLibrarySourceId());
        return series;
    }

    /** 使用短期媒体令牌打开本地影片 Range 资源。 */
    @Transactional(readOnly = true)
    public FileContentResource openPlaybackContent(String token, UUID videoItemId) {
        MediaPlaybackTokenService.MediaGrant grant = tokenService.requireGrant(token, videoItemId);
        MediaVideoItem item = requireReadableVideo(grant.requesterUserId(), videoItemId);
        FileContentResource content = fileContentAccessService.openAuthorizedMediaResource(
                item.getFileNodeId(),
                MediaContentPurpose.MEDIA_PLAYBACK
        );
        return withWebmFamilyMimeType(item, content);
    }

    /// WebM 是 Matroska 子集：av1/vp9/vp8 + opus/vorbis 的 matroska 内容
    /// 浏览器可直播，但按 x-matroska MIME 会被 video 元素拒绝；
    /// 直播判定成立时统一改按 video/webm 提供（D-007）。
    private FileContentResource withWebmFamilyMimeType(MediaVideoItem item, FileContentResource content) {
        String container = item.getContainerFormat() == null
                ? ""
                : item.getContainerFormat().trim().toLowerCase(Locale.ROOT);
        String video = item.getVideoCodec() == null
                ? ""
                : item.getVideoCodec().trim().toLowerCase(Locale.ROOT);
        String audio = item.getAudioCodec() == null
                ? ""
                : item.getAudioCodec().trim().toLowerCase(Locale.ROOT);
        boolean webmFamily = container.contains("webm") || container.contains("matroska");
        boolean webmVideo = video.equals("av1") || video.equals("vp9") || video.equals("vp8");
        boolean webmAudio = audio.isEmpty() || audio.equals("opus") || audio.equals("vorbis");
        if (webmFamily && webmVideo && webmAudio && !"video/webm".equalsIgnoreCase(content.mimeType())) {
            return new FileContentResource(
                    content.resource(),
                    content.fileName(),
                    content.sizeBytes(),
                    "video/webm"
            );
        }
        return content;
    }

    /** 校验短期令牌并返回可读影片，用于转码流。 */
    @Transactional(readOnly = true)
    public MediaVideoItem requireTokenVideo(String token, UUID videoItemId) {
        MediaPlaybackTokenService.MediaGrant grant = tokenService.requireGrant(token, videoItemId);
        return requireReadableVideo(grant.requesterUserId(), videoItemId);
    }

    /** 使用影片令牌读取与该影片关联的 MinIO 派生资源。 */
    @Transactional(readOnly = true)
    public FileContentStream openVideoAsset(String token, UUID videoItemId, UUID fileNodeId) {
        MediaPlaybackTokenService.MediaGrant grant = tokenService.requireGrant(token, videoItemId);
        MediaVideoItem item = requireReadableVideo(grant.requesterUserId(), videoItemId);
        boolean linked = contentAssetRepository.findByOwnerUserIdAndFileNodeId(item.getOwnerUserId(), fileNodeId)
                .stream()
                .anyMatch(asset -> belongsToVideo(asset, item));
        if (!linked) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "媒体令牌不能访问其他影片的派生资源");
        }
        return fileContentAccessService.openAuthorizedMediaStream(fileNodeId, MediaContentPurpose.MEDIA_ASSET);
    }

    /** 使用系列令牌读取与该系列关联的 MinIO 派生资源。 */
    @Transactional(readOnly = true)
    public FileContentStream openSeriesAsset(String token, UUID seriesId, UUID fileNodeId) {
        MediaPlaybackTokenService.MediaGrant grant = tokenService.requireSeriesGrant(token, seriesId);
        MediaTvSeries series = requireReadableSeries(grant.requesterUserId(), seriesId);
        boolean linked = contentAssetRepository.findByOwnerUserIdAndFileNodeId(series.getOwnerUserId(), fileNodeId)
                .stream()
                .anyMatch(asset -> ResourceType.TV_SERIES.getValue().equals(asset.getResourceType())
                        && seriesId.equals(asset.getResourceId()));
        if (!linked) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "媒体令牌不能访问其他系列的派生资源");
        }
        return fileContentAccessService.openAuthorizedMediaStream(fileNodeId, MediaContentPurpose.MEDIA_ASSET);
    }

    private boolean belongsToVideo(ContentAsset asset, MediaVideoItem item) {
        if (ResourceType.VIDEO_ITEM.getValue().equals(asset.getResourceType())) {
            return item.getId().equals(asset.getResourceId());
        }
        if (ResourceType.MOVIE.getValue().equals(asset.getResourceType())) {
            return item.getMovieId() != null && item.getMovieId().equals(asset.getResourceId());
        }
        if (ResourceType.TV_SERIES.getValue().equals(asset.getResourceType())) {
            return item.getSeriesId() != null && item.getSeriesId().equals(asset.getResourceId());
        }
        return false;
    }
}
