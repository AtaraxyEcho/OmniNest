package com.omninest.modules.file.dto;

import java.util.UUID;

/**
 * 上传完成受理结果。文件节点由 Worker 在安全扫描通过后创建。
 *
 * @param uploadId 上传会话标识
 * @param status 受理后状态：SCANNING 表示安全扫描中，COMPLETED 表示已入库
 * @param taskId 关联任务标识：扫描中为安全扫描任务，已完成时为媒体导入任务
 * @param fileNodeId 已入库文件节点标识，扫描中为空
 * @author OmniNest
 */
public record FileUploadCompleteResultDto(
        String uploadId,
        String status,
        UUID taskId,
        UUID fileNodeId
) {
}
