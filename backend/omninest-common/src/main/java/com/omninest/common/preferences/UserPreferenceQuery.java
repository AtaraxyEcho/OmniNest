package com.omninest.common.preferences;

import java.util.Map;
import java.util.UUID;

/**
 * 用户偏好跨模块只读查询端口。
 *
 * @author OmniNest
 */
public interface UserPreferenceQuery {

    /**
     * 查询指定作用域的偏好值。
     *
     * @param ownerUserId 用户标识
     * @param scope 偏好作用域
     * @return 不可变偏好值
     */
    Map<String, Object> findValues(UUID ownerUserId, String scope);
}
