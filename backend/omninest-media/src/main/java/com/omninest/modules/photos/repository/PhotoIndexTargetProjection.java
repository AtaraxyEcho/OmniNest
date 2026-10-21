package com.omninest.modules.photos.repository;

import java.util.UUID;

/**
 * 全站照片索引重建的候选投影。
 *
 * <p>重建只需要「谁的照片」和「照片标识」，按投影读取可避免为十万级存量照片加载整个实体图。</p>
 *
 * @author OmniNest
 */
public interface PhotoIndexTargetProjection {

    /** @return 照片标识 */
    UUID getId();

    /** @return 所有者用户标识 */
    UUID getOwnerUserId();
}
