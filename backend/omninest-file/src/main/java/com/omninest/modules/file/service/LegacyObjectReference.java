package com.omninest.modules.file.service;

/**
 * 未迁移为 FileNode 的历史对象引用。
 *
 * @param bucketName 存储桶名称
 * @param objectKey 对象键
 * @author OmniNest
 */
public record LegacyObjectReference(String bucketName, String objectKey) {
}
