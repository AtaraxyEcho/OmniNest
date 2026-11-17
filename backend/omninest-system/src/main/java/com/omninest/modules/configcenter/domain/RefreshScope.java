package com.omninest.modules.configcenter.domain;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * 配置刷新范围。
 *
 * <p>取值必须与数据库约束 {@code chk_config_entries_refresh_scope} 一致：
 * 枚举里出现库里不允许的值会在写入时被 CHECK 拒绝，库里出现枚举没有的取值
 * 会让 {@link #fromValue(String)} 抛异常。</p>
 */
@Getter
@AllArgsConstructor
public enum RefreshScope {
    /** 热更新：写入后立即对所有实例生效。 */
    HOT("HOT"),
    /** 下一次任务生效：已在执行的任务沿用旧值。 */
    NEXT_TASK("NEXT_TASK"),
    /** 需要重启：进程内已构建的客户端或连接池不会自动重建。 */
    RESTART_REQUIRED("RESTART_REQUIRED");

    private final String value;

    public static RefreshScope fromValue(String value) {
        for (RefreshScope scope : values()) {
            if (scope.value.equalsIgnoreCase(value)) {
                return scope;
            }
        }
        throw new IllegalArgumentException("未知的刷新范围: " + value);
    }
}
