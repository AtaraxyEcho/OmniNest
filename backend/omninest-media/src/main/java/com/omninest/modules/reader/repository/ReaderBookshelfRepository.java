package com.omninest.modules.reader.repository;

import com.omninest.modules.reader.domain.ReaderBookshelf;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 阅读书架仓储。
 */
public interface ReaderBookshelfRepository extends JpaRepository<ReaderBookshelf, UUID> {

    Optional<ReaderBookshelf> findByOwnerUserIdAndReaderItemId(UUID ownerUserId, UUID readerItemId);

    /**
     * 批量查询用户在指定条目上的书架记录。
     */
    List<ReaderBookshelf> findByOwnerUserIdAndReaderItemIdIn(UUID ownerUserId, Collection<UUID> readerItemIds);

    boolean existsByOwnerUserIdAndReaderItemId(UUID ownerUserId, UUID readerItemId);

    void deleteByOwnerUserIdAndReaderItemId(UUID ownerUserId, UUID readerItemId);

    void deleteByOwnerUserIdAndReaderItemIdIn(UUID ownerUserId, Collection<UUID> readerItemIds);

    void deleteByReaderItemIdIn(Collection<UUID> readerItemIds);
}
