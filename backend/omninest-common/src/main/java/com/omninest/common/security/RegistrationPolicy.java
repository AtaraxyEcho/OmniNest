package com.omninest.common.security;

/**
 * 定义普通用户注册的部署策略。
 *
 * @author OmniNest
 */
public interface RegistrationPolicy {

    /**
     * 校验当前部署是否允许普通用户注册。
     */
    void requireRegistrationEnabled();
}
