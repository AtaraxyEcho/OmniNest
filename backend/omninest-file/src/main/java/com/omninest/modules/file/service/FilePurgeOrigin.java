package com.omninest.modules.file.service;

import java.util.UUID;

/**
 * 永久删除请求的业务来源。
 *
 * @param module 模块编码
 * @param resourceId 业务资源 ID
 * @author OmniNest
 */
public record FilePurgeOrigin(String module, UUID resourceId) {
}
