package com.omninest.modules.file.event;

import java.util.UUID;

/**
 * 媒体自动导入任务消息。
 *
 * @param taskId 任务 ID
 * @param file 文件上传事件
 * @author OmniNest
 */
public record MediaAutoImportRequestedEvent(UUID taskId, FileUploadedEvent file) {
}
