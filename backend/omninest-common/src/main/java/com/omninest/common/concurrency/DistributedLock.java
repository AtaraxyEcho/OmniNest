package com.omninest.common.concurrency;

import java.time.Duration;

/**
 * 短时间分布式互斥端口。
 *
 * @author OmniNest
 */
public interface DistributedLock {

    /**
     * 创建当前持锁请求使用的唯一令牌。
     *
     * @return 唯一令牌
     */
    String newToken();

    /**
     * 尝试在指定有效期内获取锁。
     *
     * @param key 锁键
     * @param token 持锁令牌
     * @param ttl 有效期
     * @return 是否获取成功
     */
    boolean tryLock(String key, String token, Duration ttl);

    /**
     * 仅在令牌匹配时释放锁。
     *
     * @param key 锁键
     * @param token 持锁令牌
     * @return 是否释放成功
     */
    boolean unlock(String key, String token);
}
