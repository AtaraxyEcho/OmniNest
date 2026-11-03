package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.video.domain.NfoStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaNfoExport;
import com.omninest.modules.video.domain.MediaTvEpisode;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaVideoItem;
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
     * 生成并保存 NFO 文件。
     *
     * <p>读取条目、写对象存储、落库三段各自独立：NFO 上传走远程对象存储，
     * 不能压在事务里占着连接，派生元数据又是自己的独立事务，两层叠加会让
     * 一个线程同时持有两个数据库连接。</p>
     *
     * @param ownerUserId 所有者用户 ID
     * @param videoItemId 视频条目 ID
     * @return 导出结果
     */
    public NfoExportDto export(UUID ownerUserId, UUID videoItemId) {
        String content = transactionTemplate.execute(status -> {
            MediaVideoItem item = requireVideoItem(ownerUserId, videoItemId);
            return buildNfo(item);
        });
        // NFO 必须真的落盘：此前只把一个从未写过的路径写进 export_path，
        // 接口声称"导出为文件"，库里却没有任何可取得的对象。
        UUID storedFileNodeId = derivedAssetStorageService.store(
                ownerUserId,
                "VIDEO_ITEM",
                videoItemId,
                "NFO",
                "nfo-" + videoItemId + ".nfo",
                "application/xml",
                new ByteArrayInputStream(content.getBytes(StandardCharsets.UTF_8))
        );
        return transactionTemplate.execute(status -> {
            MediaVideoItem item = requireVideoItem(ownerUserId, videoItemId);
            MediaNfoExport export = nfoExportRepository
                    .findTopByOwnerUserIdAndVideoItemIdOrderByUpdatedAtDesc(ownerUserId, videoItemId)
                    .orElseGet(MediaNfoExport::new);
            export.setOwnerUserId(ownerUserId);
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

    private MediaVideoItem requireVideoItem(UUID ownerUserId, UUID videoItemId) {
        return videoItemRepository.findByIdAndOwnerUserId(videoItemId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在"));
    }

    @Transactional(readOnly = true)
    public NfoExportDto preview(UUID ownerUserId, UUID videoItemId) {
        MediaVideoItem item = videoItemRepository.findByIdAndOwnerUserId(videoItemId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.MEDIA_NOT_FOUND, "媒体资源不存在"));
        return new NfoExportDto(
                null, videoItemId, item.getNfoStatus(), item.getNfoPath(), item.getNfoUpdatedAt(), buildNfo(item));
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
}
