package com.omninest.modules.quota.service;

import com.omninest.common.config.BaseRuntimeConfigService;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.modules.quota.QuotaStatus;
import com.omninest.modules.quota.port.StorageQuotaPolicy;
import org.springframework.stereotype.Service;

/**
 * 基于配置中心的存储配额运行策略实现。
 *
 * @author OmniNest
 */
@Service
public class RuntimeStorageQuotaPolicy extends BaseRuntimeConfigService implements StorageQuotaPolicy {

    private static final String CONFIG_KEY_DEFAULT_QUOTA_GB = "storage.quota.default";
    private static final String CONFIG_KEY_WARNING_PERCENT = "storage.quota.warning";
    private static final String LEGACY_DEFAULT_QUOTA_GB = "storage.quota.default.gb";
    private static final String LEGACY_WARNING_PERCENT = "storage.quota.warning.percent";
    private static final int DEFAULT_QUOTA_GB = 10;
    private static final long GB_TO_BYTES = 1024L * 1024 * 1024;
    private static final int DEFAULT_WARNING_PERCENT = 80;

    /**
     * 创建基于运行时配置的配额策略。
     *
     * @param configValueProvider 配置值查询端口
     * @param runtimeConfigCache 运行时配置缓存端口
     */
    public RuntimeStorageQuotaPolicy(
            ConfigValueProvider configValueProvider,
            RuntimeConfigCache runtimeConfigCache
    ) {
        super(configValueProvider, runtimeConfigCache);
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public long defaultQuotaBytes() {
        int quotaGigabytes = intWithLegacy(CONFIG_KEY_DEFAULT_QUOTA_GB, LEGACY_DEFAULT_QUOTA_GB, DEFAULT_QUOTA_GB);
        return (long) quotaGigabytes * GB_TO_BYTES;
    }

    /**
     * {@inheritDoc}
     */
    @Override
    public QuotaStatus resolveStatus(long usedBytes, long quotaBytes, boolean superAdmin) {
        if (superAdmin || quotaBytes <= 0) {
            return QuotaStatus.NORMAL;
        }
        int warningPercent = intWithLegacy(CONFIG_KEY_WARNING_PERCENT, LEGACY_WARNING_PERCENT, DEFAULT_WARNING_PERCENT);
        int normalizedWarningPercent = Math.max(50, Math.min(99, warningPercent));
        return QuotaStatus.resolve(usedBytes, quotaBytes, normalizedWarningPercent);
    }

    private int intWithLegacy(String key, String legacyKey, int defaultValue) {
        return cachedConfigValue(key)
                .or(() -> cachedConfigValue(legacyKey))
                .map(value -> parseInt(value, defaultValue))
                .orElse(defaultValue);
    }
}
