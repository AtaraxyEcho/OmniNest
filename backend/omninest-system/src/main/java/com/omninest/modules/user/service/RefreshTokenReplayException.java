package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;

/**
 * 刷新令牌重放：会话撤销状态已写在当前事务持有的会话行上，必须随事务提交。
 *
 * <p>重放分支已经通过 {@code PESSIMISTIC_WRITE} 持有会话行锁，若在独立事务中更新
 * 同一行会自死锁；因此改为在当前事务内更新并由本异常声明不回滚。</p>
 *
 * @author OmniNest
 */
class RefreshTokenReplayException extends BusinessException {

    RefreshTokenReplayException(String message) {
        super(ErrorCode.UNAUTHORIZED, message);
    }
}
