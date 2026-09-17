package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.ShareLink;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ShareLinkRepository extends JpaRepository<ShareLink, UUID> {
    List<ShareLink> findByOwnerUserIdAndDisabledAtIsNullOrderByCreatedAtDesc(UUID ownerUserId);

    @Query("""
            select s from ShareLink s
            where s.ownerUserId = :ownerUserId and s.disabledAt is null
            order by s.createdAt desc
            """)
    Page<ShareLink> findActiveByOwnerPage(
            @Param("ownerUserId") UUID ownerUserId,
            Pageable pageable);

    List<ShareLink> findByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId);

    Optional<ShareLink> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    List<ShareLink> findByOwnerUserIdAndResourceIdIn(UUID ownerUserId, Collection<UUID> resourceIds);

    Optional<ShareLink> findByTokenHash(String tokenHash);

    List<ShareLink> findByResourceIdAndDisabledAtIsNull(UUID resourceId);

    /**
     * 批量禁用指定资源的所有分享链接。
     */
    @Modifying(clearAutomatically = true)
    @Query("UPDATE ShareLink s SET s.disabledAt = :now WHERE s.resourceId = :resourceId AND s.disabledAt IS NULL")
    void disableByResourceId(@Param("resourceId") UUID resourceId, @Param("now") Instant now);

    /**
     * 在链接仍有效且未达到上限时原子消费一次访问次数。
     *
     * @param shareId 分享链接 ID
     * @param now 当前时间
     * @return 成功消费时为 1，否则为 0
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE ShareLink s
            SET s.accessCount = s.accessCount + 1,
                s.updatedAt = :now,
                s.version = s.version + 1
            WHERE s.id = :shareId
              AND s.disabledAt IS NULL
              AND (s.expiresAt IS NULL OR s.expiresAt > :now)
              AND (s.maxAccessCount IS NULL OR s.accessCount < s.maxAccessCount)
            """)
    int consumeAccess(@Param("shareId") UUID shareId, @Param("now") Instant now);
}
