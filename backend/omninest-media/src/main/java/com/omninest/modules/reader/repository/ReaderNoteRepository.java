package com.omninest.modules.reader.repository;

import com.omninest.modules.reader.domain.ReaderNote;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 阅读笔记仓储。
 */
public interface ReaderNoteRepository extends JpaRepository<ReaderNote, UUID> {

    List<ReaderNote> findByOwnerUserIdAndReaderItemIdOrderByCreatedAtDesc(UUID ownerUserId, UUID readerItemId);

    Optional<ReaderNote> findByOwnerUserIdAndReaderItemIdAndClientOperationId(
            UUID ownerUserId,
            UUID readerItemId,
            String clientOperationId
    );

    void deleteByOwnerUserIdAndId(UUID ownerUserId, UUID id);

    void deleteByOwnerUserIdAndReaderItemIdIn(UUID ownerUserId, Collection<UUID> readerItemIds);

    void deleteByReaderItemIdIn(Collection<UUID> readerItemIds);
}
