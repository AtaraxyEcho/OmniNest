package com.omninest.modules.reader.service;

import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.media.service.MediaImportHandler;
import com.omninest.modules.media.service.MediaImportResult;
import com.omninest.modules.reader.domain.ReaderItem;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 阅读自动导入服务：监听文件上传事件，自动导入 EPUB/TXT 文件。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class ReaderAutoImportService implements MediaImportHandler {

    private final ReaderImportService importService;
    private final ReaderFileDetector fileDetector;
    private final ReaderRuntimeConfigService configService;

    @Override
    public String module() {
        return "READER";
    }

    @Override
    public boolean supports(FileUploadedEvent event) {
        return configService.autoImportEnabled() && fileDetector.isReaderFile(event.fileName());
    }

    @Override
    public MediaImportResult importFile(FileUploadedEvent event) {
        ReaderItem item = importService.importFile(event.ownerUserId(), event.fileNodeId());
        return new MediaImportResult(module(), item.getId());
    }

    /**
     * 处理文件上传事件，自动导入阅读文件。
     *
     * @param event 文件上传事件
     * @return 导入成功时返回条目 ID，否则返回 empty
     */
    public Optional<UUID> importUploadedFile(FileUploadedEvent event) {
        if (!supports(event)) {
            return Optional.empty();
        }
        return Optional.of(importFile(event).resourceId());
    }
}
