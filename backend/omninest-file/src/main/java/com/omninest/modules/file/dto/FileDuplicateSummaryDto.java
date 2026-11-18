package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;

/**
 * 当前用户个人空间中可由重复内容释放的存储摘要。
 *
 * @param duplicateFileCount 重复副本数（每组保留一个原件）
 * @param duplicateGroupCount 重复内容组数
 * @param reclaimableBytes 可释放字节数
 * @param filesWithoutVerifiedHash 未能按服务端摘要核对的活动文件数
 */
@Schema(description = "当前用户个人空间中的重复文件摘要")
public record FileDuplicateSummaryDto(
        long duplicateFileCount,
        long duplicateGroupCount,
        long reclaimableBytes,
        long filesWithoutVerifiedHash
) {
}
