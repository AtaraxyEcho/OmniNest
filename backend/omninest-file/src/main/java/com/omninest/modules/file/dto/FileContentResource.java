package com.omninest.modules.file.dto;

import org.springframework.core.io.Resource;

/**
 * 可由 HTTP Range 响应读取的文件资源。
 *
 * @param resource Spring 资源
 * @param fileName 文件名称
 * @param sizeBytes 文件大小
 * @param mimeType MIME 类型
 * @author OmniNest
 */
public record FileContentResource(Resource resource, String fileName, long sizeBytes, String mimeType) {
}
