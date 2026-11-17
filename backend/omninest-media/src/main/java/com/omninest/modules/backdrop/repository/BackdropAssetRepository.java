package com.omninest.modules.backdrop.repository;

import com.omninest.modules.backdrop.domain.BackdropAsset;
import com.omninest.modules.backdrop.domain.BackdropAssetStatus;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 背景素材仓储。
 *
 * @author OmniNest
 */
public interface BackdropAssetRepository extends JpaRepository<BackdropAsset, UUID> {

    /**
     * 按素材 ID 与归属用户查询，用于归属校验与统一 404 防资源枚举。
     *
     * @param id 素材 ID
     * @param ownerUserId 归属用户 ID
     * @return 命中的素材
     */
    Optional<BackdropAsset> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    /**
     * 按归属用户与内容摘要查询，用于上传去重。
     *
     * @param ownerUserId 归属用户 ID
     * @param sha256 服务端计算的素材摘要
     * @return 命中的素材
     */
    Optional<BackdropAsset> findByOwnerUserIdAndSha256(UUID ownerUserId, String sha256);

    /**
     * 统计用户可用素材数量（排除 FAILED），用于数量配额检查。
     *
     * @param ownerUserId 归属用户 ID
     * @param status 需要排除的状态
     * @return 素材数量
     */
    long countByOwnerUserIdAndStatusNot(UUID ownerUserId, BackdropAssetStatus status);

    /**
     * 按更新时间倒序查询用户的背景素材。
     *
     * @param ownerUserId 归属用户 ID
     * @return 素材列表
     */
    List<BackdropAsset> findByOwnerUserIdOrderByUpdatedAtDesc(UUID ownerUserId);
}
