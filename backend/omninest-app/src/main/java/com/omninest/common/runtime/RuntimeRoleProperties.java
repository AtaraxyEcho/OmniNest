package com.omninest.common.runtime;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 暴露当前进程的运行角色配置。
 *
 * @author OmniNest
 */
@Getter
@Setter
@ConfigurationProperties(prefix = "omninest.runtime")
public class RuntimeRoleProperties {
    private RuntimeRole role = RuntimeRole.API;
}
