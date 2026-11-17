package com.omninest.modules.reader.repository;

import com.omninest.modules.reader.domain.ReaderBookmark;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 阅读书签仓储。
 */
public interface ReaderBookmarkRepository extends JpaRepository<ReaderBookmark, UUID> {

    List<ReaderBookmark> findByOwnerUserIdAndReaderItemIdOrderByCreatedAtDesc(UUID ownerUserId, UUID readerItemId);

    List<ReaderBookmark> findByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId);

    Optional<ReaderBookmark> findByOwnerUserIdAndReaderItemIdAndClientOperationId(
            UUID ownerUserId,
            UUID readerItemId,
            String clientOperationId
    );

    void deleteByOwnerUserIdAndId(UUID ownerUserId, UUID id);

    void deleteByOwnerUserIdAndReaderItemIdIn(UUID ownerUserId, Collection<UUID> readerItemIds);

    void deleteByReaderItemIdIn(Collection<UUID> readerItemIds);
}
