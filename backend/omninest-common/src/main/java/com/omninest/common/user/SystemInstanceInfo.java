package com.omninest.common.user;

import java.time.ZoneId;

/**
 * 系统实例配置的跨模块只读端口。
 *
 * <p>安装向导写入的实例名、默认语言与时区需要被通知、媒体等模块读取，
 * 但直接依赖 user 模块的实现类会与 user→notification 的既有依赖成环，
 * 因此统一走本端口，由 user 模块提供实现。</p>
 *
 * @author OmniNest
 */
public interface SystemInstanceInfo {

    /**
     * 实例时区；配置缺失或非法时回退 JVM 默认时区。
     *
     * @return 实例时区
     */
    ZoneId timeZone();

    /**
     * 实例默认语言标签。
     *
     * @return 形如 zh-CN 的语言标签
     */
    String defaultLocale();

    /**
     * 实例展示名。
     *
     * @return 实例名
     */
    String instanceName();
}
