package com.omninest.modules.photos.repository;

import jakarta.persistence.EntityManager;
import java.util.Locale;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Repository;

/**
 * 使用 PostgreSQL 事务级 advisory lock 协调跨实例的内容去重导入。
 *
 * @author OmniNest
 */
@Repository
@RequiredArgsConstructor
public class PhotoItemImportLockQueryImpl implements PhotoItemImportLockQuery {

    private final EntityManager entityManager;

    @Override
    public void lockContentHashForImport(UUID ownerUserId, String contentHash) {
        String lockKey = ownerUserId + ":" + contentHash.toLowerCase(Locale.ROOT);
        entityManager.createNativeQuery("""
                WITH content_lock AS MATERIALIZED (
                    SELECT pg_advisory_xact_lock(hashtextextended(CAST(:lockKey AS text), 0))
                )
                SELECT 1 FROM content_lock
                """)
                .setParameter("lockKey", lockKey)
                .getSingleResult();
    }
}
