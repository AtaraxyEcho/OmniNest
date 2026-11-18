package com.omninest.modules.quota.port;

/**
 * 按内容类别汇总的对象存储字节数。
 *
 * @param category 稳定的类别编码
 * @param usedBytes 该类别实际占用的字节数
 */
public record StorageCategoryMetric(String category, long usedBytes) {
}
