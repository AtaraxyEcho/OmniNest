package com.omninest.modules.video.service;

import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.media.service.MediaImportHandler;
import com.omninest.modules.media.service.MediaImportResult;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 视频文件自动导入服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class MovieAutoImportService implements MediaImportHandler {
    private final MediaRuntimeConfigService configService;
    private final MovieScrapeService scrapeService;
    private final SimpleFileNameParser fileNameParser;

    @Override
    public String module() {
        return "MOVIES";
    }

    @Override
    public boolean supports(FileUploadedEvent event) {
        return configService.autoImportEnabled()
                && fileNameParser.isVideoFile(event.fileName(), event.mimeType());
    }

    @Override
    public MediaImportResult importFile(FileUploadedEvent event) {
        UUID videoItemId = scrapeService.registerPendingVideo(
                event.ownerUserId(),
                event.fileNodeId()
        ).getId();
        return new MediaImportResult(module(), videoItemId);
    }

    /**
     * 兼容调用方的可选导入入口。
     *
     * @param event 文件上传事件
     * @return 不支持时返回空，成功时返回资源 ID
     */
    public Optional<UUID> importUploadedFile(FileUploadedEvent event) {
        if (!supports(event)) {
            return Optional.empty();
        }
        return Optional.of(importFile(event).resourceId());
    }
}
