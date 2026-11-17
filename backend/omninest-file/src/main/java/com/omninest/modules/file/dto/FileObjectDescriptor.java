package com.omninest.modules.file.dto;

import java.util.UUID;

/**
 * 跨模块使用的不可变文件对象描述符。
 *
 * @param id 文件对象 ID
 * @param bucketName 对象存储桶名称
 * @param objectKey 对象键
 * @param sha256 内容摘要
 * @param sizeBytes 对象字节数
 * @param mimeType MIME 类型
 * @author OmniNest
 */
public record FileObjectDescriptor(
        UUID id,
        String bucketName,
        String objectKey,
        String sha256,
        long sizeBytes,
        String mimeType
) {
}
