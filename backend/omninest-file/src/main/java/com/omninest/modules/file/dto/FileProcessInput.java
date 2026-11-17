package com.omninest.modules.file.dto;

import java.util.UUID;

/**
 * 受信任媒体进程可读取的文件输入。
 *
 * @param fileId 文件节点 ID
 * @param providerType 内容提供者类型
 * @param input 进程输入 URL 或只读容器路径
 * @author OmniNest
 */
public record FileProcessInput(UUID fileId, String providerType, String input) {
}
