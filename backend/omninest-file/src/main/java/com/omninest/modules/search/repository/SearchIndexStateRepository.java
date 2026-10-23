package com.omninest.modules.search.repository;

import com.omninest.modules.search.domain.SearchIndexState;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 搜索索引状态仓储
 */
public interface SearchIndexStateRepository extends JpaRepository<SearchIndexState, UUID> {

    Optional<SearchIndexState> findByOwnerUserIdIsNull();

    /**
     * 删除指定用户的索引状态行（用户删除时清理）。
     *
     * @param ownerUserId 用户 ID
     */
    void deleteByOwnerUserId(UUID ownerUserId);
}
