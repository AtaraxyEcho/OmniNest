package com.omninest.modules.photos.repository;

import java.util.UUID;

/**
 * 照片导入时用于串行化同一所有者与内容摘要的仓储操作。
 *
 * <p>刻意不加 {@code @NoRepositoryBean}：Spring Data 的片段探测会把带该注解的接口直接排除，
 * 导致本接口的方法退回派生查询解析（{@code PhotoItem} 上没有对应属性即启动失败），
 * 而它并不继承 {@code Repository}，不会被仓储扫描误认作仓储。</p>
 *
 * @author OmniNest
 */
public interface PhotoItemImportLockQuery {

    /**
     * 在当前事务结束前锁定该用户的内容摘要，避免并发导入同时通过去重检查。
     *
     * @param ownerUserId 媒体所有者
     * @param contentHash 内容 SHA-256
     */
    void lockContentHashForImport(UUID ownerUserId, String contentHash);
}
