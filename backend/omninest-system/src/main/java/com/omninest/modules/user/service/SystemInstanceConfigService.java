package com.omninest.modules.user.service;

import com.omninest.common.user.SystemInstanceInfo;
import com.omninest.modules.user.domain.SystemInstance;
import com.omninest.modules.user.repository.SystemInstanceRepository;
import java.time.DateTimeException;
import java.time.ZoneId;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 安装向导写入的系统实例配置读取入口。
 *
 * <p>时间线、阅读统计与管理台日期分桶必须使用同一份实例时区，
 * 不能各自读 JVM 默认时区；实例配置缺失时回退到 JVM 默认值。</p>
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class SystemInstanceConfigService implements SystemInstanceInfo {

    private static final String FALLBACK_LOCALE = "zh-CN";
    private static final String FALLBACK_INSTANCE_NAME = "OmniNest";

    private final SystemInstanceRepository systemInstanceRepository;

    /**
     * 读取实例时区；配置非法或尚未初始化时回退 JVM 默认时区。
     *
     * @return 实例时区
     */
    @Override
    @Transactional(readOnly = true)
    public ZoneId timeZone() {
        SystemInstance instance = instance();
        if (instance == null || instance.getDefaultTimezone() == null) {
            return ZoneId.systemDefault();
        }
        try {
            return ZoneId.of(instance.getDefaultTimezone());
        } catch (DateTimeException exception) {
            return ZoneId.systemDefault();
        }
    }

    /**
     * 读取实例默认语言。
     *
     * @return 默认语言
     */
    @Override
    @Transactional(readOnly = true)
    public String defaultLocale() {
        SystemInstance instance = instance();
        if (instance == null || instance.getDefaultLocale() == null
                || instance.getDefaultLocale().isBlank()) {
            return FALLBACK_LOCALE;
        }
        return instance.getDefaultLocale();
    }

    /**
     * 读取实例名称。
     *
     * @return 实例名称
     */
    @Override
    @Transactional(readOnly = true)
    public String instanceName() {
        SystemInstance instance = instance();
        if (instance == null || instance.getInstanceName() == null
                || instance.getInstanceName().isBlank()) {
            return FALLBACK_INSTANCE_NAME;
        }
        return instance.getInstanceName();
    }

    private SystemInstance instance() {
        return systemInstanceRepository.findById(SystemInstance.SINGLETON_ID).orElse(null);
    }
}
