package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaNfoExport;
import com.omninest.modules.video.domain.MediaTvEpisode;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.domain.NfoStatus;
import com.omninest.modules.video.dto.MovieDtos.NfoExportDto;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaNfoExportRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import jakarta.annotation.PostConstruct;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

@Service
@RequiredArgsConstructor
public class MovieNfoService {
    private final MediaVideoItemRepository videoItemRepository;
    private final MediaNfoExportRepository nfoExportRepository;
    private final MediaMovieRepository movieRepository;
    private final MediaTvEpisodeRepository episodeRepository;
    private final MediaTvSeriesRepository tvSeriesRepository;
    private final DerivedAssetStorageService derivedAssetStorageService;
    private final MediaContentAccessService mediaContentAccessService;
    private final MediaLibraryAccessService mediaLibraryAccessService;
    private final PlatformTransactionManager transactionManager;

    private TransactionTemplate transactionTemplate;

    /**
     * 初始化 NFO 导出使用的短事务模板。
     */
    @PostConstruct
    void initTransactionTemplate() {
        this.transactionTemplate = new TransactionTemplate(transactionManager);
    }

    /**
     * 生成并保存单条视频（电影或分集）的 NFO 文件。
     *
     * <p>读取条目、写对象存储、落库三段各自独立：NFO 上传走远程对象存储，
     * 不能压在事务里占着连接，派生元数据又是自己的独立事务，两层叠加会让
     * 一个线程同时持有两个数据库连接。</p>
     *
     * @param operatorUserId 操作者用户 ID
     * @param videoItemId 视频条目 ID
     * @return 导出结果
     */
    public NfoExportDto export(UUID operatorUserId, UUID videoItemId) {
        PreparedNfo prepared = transactionTemplate.execute(status -> {
            MediaVideoItem item = requireWritableVideo(operatorUserId, videoItemId);
            return new PreparedNfo(item.getOwnerUserId(), buildNfo(item));
        });
        UUID catalogOwnerId = prepared.catalogOwnerId();
        String content = prepared.content();
        UUID storedFileNodeId = derivedAssetStorageService.store(
                catalogOwnerId,
                "VIDEO_ITEM",
                videoItemId,
                "NFO",
                "nfo-" + videoItemId + ".nfo",
                "application/xml",
                new ByteArrayInputStream(content.getBytes(StandardCharsets.UTF_8))
        );
        return transactionTemplate.execute(status -> {
            MediaVideoItem item = requireWritableVideo(operatorUserId, videoItemId);
            UUID ownerId = item.getOwnerUserId();
            MediaNfoExport export = nfoExportRepository
                    .findTopByOwnerUserIdAndVideoItemIdOrderByUpdatedAtDesc(ownerId, videoItemId)
                    .orElseGet(MediaNfoExport::new);
            export.setOwnerUserId(ownerId);
            export.setVideoItemId(videoItemId);
            export.setExportPath(storedFileNodeId.toString());
            export.setStatus(NfoStatus.GENERATED.getValue());
            export.setErrorSummary(null);
            export.setExportedAt(Instant.now());
            nfoExportRepository.save(export);
            item.setNfoStatus(NfoStatus.GENERATED.getValue());
            item.setNfoPath(export.getExportPath());
            item.setNfoUpdatedAt(export.getExportedAt());
            videoItemRepository.save(item);
            return new NfoExportDto(export.getId(), videoItemId, export.getStatus(),
                    export.getExportPath(), export.getExportedAt(), content);
        });
    }

    @Transactional(readOnly = true)
    public NfoExportDto preview(UUID requesterUserId, UUID videoItemId) {
        MediaVideoItem item = mediaContentAccessService.requireReadableVideo(requesterUserId, videoItemId);
        return new NfoExportDto(
                null, videoItemId, item.getNfoStatus(), item.getNfoPath(), item.getNfoUpdatedAt(), buildNfo(item));
    }

    /**
     * 预览系列级 {@code <tvshow>} NFO。
     *
     * @param requesterUserId 请求者用户 ID
     * @param seriesId 系列 ID
     * @return 系列 NFO 预览结果
     */
    @Transactional(readOnly = true)
    public NfoExportDto previewSeries(UUID requesterUserId, UUID seriesId) {
        MediaTvSeries series = requireReadableSeries(requesterUserId, seriesId);
        return new NfoExportDto(
                null,
                seriesId,
                NfoStatus.GENERATED.getValue(),
                null,
                series.getUpdatedAt(),
                buildSeriesNfo(series)
        );
    }

    /**
     * 生成并保存系列级标准 {@code <tvshow>} NFO 文件。
     *
     * @param operatorUserId 操作者用户 ID
     * @param seriesId 系列 ID
     * @return 系列 NFO 导出结果
     */
    public NfoExportDto exportSeries(UUID operatorUserId, UUID seriesId) {
        PreparedNfo prepared = transactionTemplate.execute(status -> {
            MediaTvSeries series = requireWritableSeries(operatorUserId, seriesId);
            return new PreparedNfo(series.getOwnerUserId(), buildSeriesNfo(series));
        });
        UUID catalogOwnerId = prepared.catalogOwnerId();
        String content = prepared.content();
        UUID storedFileNodeId = derivedAssetStorageService.store(
                catalogOwnerId,
                "TV_SERIES",
                seriesId,
                "NFO",
                "tvshow-" + seriesId + ".nfo",
                "application/xml",
                new ByteArrayInputStream(content.getBytes(StandardCharsets.UTF_8))
        );
        return new NfoExportDto(
                null,
                seriesId,
                NfoStatus.GENERATED.getValue(),
                storedFileNodeId.toString(),
                Instant.now(),
                content
        );
    }

    private MediaVideoItem requireWritableVideo(UUID operatorUserId, UUID videoItemId) {
        MediaVideoItem item = videoItemRepository.findById(videoItemId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在"));
        if (item.getOwnerUserId().equals(operatorUserId)) {
            return item;
        }
        if (mediaContentAccessService.findReadableVideo(operatorUserId, videoItemId).isEmpty()) {
            throw new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在");
        }
        if (item.getLibrarySourceId() != null) {
            try {
                mediaLibraryAccessService.requireManage(operatorUserId, item.getLibrarySourceId());
                return item;
            } catch (BusinessException exception) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "无权导出该媒体资源 NFO");
            }
        }
        throw new BusinessException(ErrorCode.FORBIDDEN, "无权导出该媒体资源 NFO");
    }

    private MediaTvSeries requireReadableSeries(UUID requesterUserId, UUID seriesId) {
        var scope = mediaLibraryAccessService.visibilityScope(requesterUserId);
        return tvSeriesRepository.findActiveReadableById(
                        seriesId,
                        requesterUserId,
                        scope.sharedSpaceReadable(),
                        SpaceType.SHARED,
                        scope.librarySourceIds()
                )
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "剧集不存在"));
    }

    private MediaTvSeries requireWritableSeries(UUID operatorUserId, UUID seriesId) {
        MediaTvSeries series = tvSeriesRepository.findById(seriesId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "剧集不存在"));
        if (series.getOwnerUserId().equals(operatorUserId)) {
            return series;
        }
        requireReadableSeries(operatorUserId, seriesId);
        if (series.getLibrarySourceId() != null) {
            try {
                mediaLibraryAccessService.requireManage(operatorUserId, series.getLibrarySourceId());
                return series;
            } catch (BusinessException exception) {
                throw new BusinessException(ErrorCode.FORBIDDEN, "无权导出该剧集 NFO");
            }
        }
        throw new BusinessException(ErrorCode.FORBIDDEN, "无权导出该剧集 NFO");
    }

    private String buildSeriesNfo(MediaTvSeries series) {
        StringBuilder xml = new StringBuilder();
        xml.append("<tvshow>\n");
        xml.append("  <title>").append(escapeXml(series.getTitle())).append("</title>\n");
        xml.append("  <originaltitle>").append(escapeXml(series.getOriginalTitle())).append("</originaltitle>\n");
        xml.append("  <plot>").append(escapeXml(series.getOverview())).append("</plot>\n");
        if (series.getFirstAirDate() != null) {
            xml.append("  <premiered>").append(escapeXml(series.getFirstAirDate().toString())).append("</premiered>\n");
            xml.append("  <year>").append(series.getFirstAirDate().getYear()).append("</year>\n");
        }
        if (series.getRating() != null) {
            xml.append("  <rating>").append(series.getRating()).append("</rating>\n");
        }
        if (series.getContentRating() != null && !series.getContentRating().isBlank()) {
            xml.append("  <mpaa>").append(escapeXml(series.getContentRating())).append("</mpaa>\n");
        }
        if (series.getGenres() != null) {
            for (Map<String, Object> genre : series.getGenres()) {
                Object name = genre == null ? null : genre.get("name");
                if (name != null && !name.toString().isBlank()) {
                    xml.append("  <genre>").append(escapeXml(name.toString())).append("</genre>\n");
                }
            }
        }
        if (series.getCastMembers() != null) {
            for (Map<String, Object> member : series.getCastMembers()) {
                Object name = member == null ? null : member.get("name");
                if (name != null && !name.toString().isBlank()) {
                    xml.append("  <actor>\n");
                    xml.append("    <name>").append(escapeXml(name.toString())).append("</name>\n");
                    Object role = member.get("character");
                    if (role != null && !role.toString().isBlank()) {
                        xml.append("    <role>").append(escapeXml(role.toString())).append("</role>\n");
                    }
                    xml.append("  </actor>\n");
                }
            }
        }
        xml.append("</tvshow>\n");
        return xml.toString();
    }

    private String buildNfo(MediaVideoItem item) {
        boolean isEpisode = MediaType.EPISODE.getValue().equals(item.getMediaType());
        String root = isEpisode ? "episodedetails" : "movie";
        String title;
        String originalTitle = null;
        String overview = null;
        Integer runtimeSeconds = null;

        if (isEpisode && item.getEpisodeId() != null) {
            MediaTvEpisode ep = episodeRepository.findById(item.getEpisodeId()).orElse(null);
            if (ep != null) {
                title = ep.getTitle();
                originalTitle = ep.getOriginalTitle();
                overview = ep.getOverview();
                runtimeSeconds = ep.getRuntimeSeconds();
            } else {
                title = "第 " + (item.getEpisodeNumber() != null ? item.getEpisodeNumber() : 0) + " 集";
            }
        } else if (!isEpisode && item.getMovieId() != null) {
            MediaMovie movie = movieRepository.findById(item.getMovieId()).orElse(null);
            if (movie != null) {
                title = movie.getTitle();
                originalTitle = movie.getOriginalTitle();
                overview = movie.getOverview();
                runtimeSeconds = movie.getRuntimeSeconds();
            } else {
                title = "未知";
            }
        } else {
            title = "未知";
        }

        return "<" + root + ">\n"
                + "  <title>" + escapeXml(title) + "</title>\n"
                + "  <originaltitle>" + escapeXml(originalTitle) + "</originaltitle>\n"
                + "  <plot>" + escapeXml(overview) + "</plot>\n"
                + "  <runtime>" + (runtimeSeconds == null ? "" : runtimeSeconds / 60) + "</runtime>\n"
                + "</" + root + ">\n";
    }

    private String escapeXml(String value) {
        if (value == null) {
            return "";
        }
        return value.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&apos;");
    }

    private record PreparedNfo(UUID catalogOwnerId, String content) {
    }
}
