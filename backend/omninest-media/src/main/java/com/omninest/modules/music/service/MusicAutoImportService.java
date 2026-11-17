package com.omninest.modules.music.service;

import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.media.service.MediaImportHandler;
import com.omninest.modules.media.service.MediaImportResult;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 音乐文件自动导入服务，上传音频文件后自动创建音乐条目。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicAutoImportService implements MediaImportHandler {

    private static final Set<String> AUDIO_MIME_PREFIXES = Set.of(
            "audio/mpeg", "audio/mp3", "audio/flac", "audio/ogg",
            "audio/aac", "audio/wav", "audio/x-wav", "audio/mp4",
            "audio/x-m4a", "audio/webm"
    );

    private static final Set<String> AUDIO_EXTENSIONS = Set.of(
            "mp3", "flac", "ogg", "aac", "wav", "m4a", "wma", "opus"
    );

    private final MusicAdminService musicAdminService;
    private final MusicRuntimeConfigService configService;

    @Override
    public String module() {
        return "MUSIC";
    }

    @Override
    public boolean supports(FileUploadedEvent event) {
        return configService.autoImportEnabled() && isAudioFile(event.fileName(), event.mimeType());
    }

    @Override
    public MediaImportResult importFile(FileUploadedEvent event) {
        musicAdminService.importSingleAudioFile(event.ownerUserId(), event.fileNodeId());
        log.info("音乐自动导入完成: fileNodeId={}, fileName={}",
                event.fileNodeId(), event.fileName());
        return new MediaImportResult(module(), event.fileNodeId());
    }

    /**
     * 尝试自动导入上传的音频文件。
     * 如果是音频文件，触发单文件导入并返回导入的 track ID。
     */
    public Optional<UUID> importUploadedFile(FileUploadedEvent event) {
        if (!supports(event)) {
            return Optional.empty();
        }
        return Optional.of(importFile(event).resourceId());
    }

    private boolean isAudioFile(String fileName, String mimeType) {
        if (mimeType != null) {
            String lower = mimeType.toLowerCase(Locale.ROOT);
            if (AUDIO_MIME_PREFIXES.stream().anyMatch(lower::startsWith)) {
                return true;
            }
        }
        if (fileName != null) {
            String ext = getFileExtension(fileName).toLowerCase(Locale.ROOT);
            return AUDIO_EXTENSIONS.contains(ext);
        }
        return false;
    }

    private String getFileExtension(String fileName) {
        int dot = fileName.lastIndexOf('.');
        return dot >= 0 ? fileName.substring(dot + 1) : "";
    }
}
