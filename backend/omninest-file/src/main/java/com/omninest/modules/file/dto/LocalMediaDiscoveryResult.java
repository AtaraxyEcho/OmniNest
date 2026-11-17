package com.omninest.modules.file.dto;

/**
 * 本地媒体流式发现汇总。
 *
 * @param scannedFileCount 已检查普通文件数
 * @param videoCount 已发现视频数
 */
public record LocalMediaDiscoveryResult(int scannedFileCount, int videoCount) {
}
