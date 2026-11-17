package com.omninest.common.security;

import com.omninest.common.config.SecurityProperties;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 使用部署配置控制普通用户注册入口。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class ConfiguredRegistrationPolicy implements RegistrationPolicy {
    private final SecurityProperties securityProperties;

    /**
     * {@inheritDoc}
     */
    @Override
    public void requireRegistrationEnabled() {
        if (!securityProperties.isRegistrationEnabled()) {
            throw new BusinessException(ErrorCode.REGISTRATION_DISABLED, "当前实例未开放用户注册");
        }
    }
}
