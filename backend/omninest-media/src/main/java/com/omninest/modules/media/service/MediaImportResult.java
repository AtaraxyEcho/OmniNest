package com.omninest.modules.media.service;

import java.util.UUID;

/**
 * 媒体自动导入处理器结果。
 *
 * @param module 模块编码
 * @param resourceId 导入后资源 ID
 * @author OmniNest
 */
public record MediaImportResult(String module, UUID resourceId) {
}
