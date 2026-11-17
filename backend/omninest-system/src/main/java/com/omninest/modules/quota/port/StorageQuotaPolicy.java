package com.omninest.modules.quota.port;

import com.omninest.modules.quota.QuotaStatus;

/**
 * 存储配额运行策略端口，向调用方提供默认配额和状态计算规则。
 *
 * @author OmniNest
 */
public interface StorageQuotaPolicy {

    /**
     * 获取新用户默认存储配额。
     *
     * @return 默认配额字节数
     */
    long defaultQuotaBytes();

    /**
     * 根据当前用量和配额计算状态。
     *
     * @param usedBytes 已使用字节数
     * @param quotaBytes 配额字节数
     * @param superAdmin 是否为超级管理员
     * @return 配额状态
     */
    QuotaStatus resolveStatus(long usedBytes, long quotaBytes, boolean superAdmin);
}
