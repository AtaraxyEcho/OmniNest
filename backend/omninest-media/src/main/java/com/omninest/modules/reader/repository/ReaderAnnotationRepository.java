package com.omninest.modules.reader.repository;

import com.omninest.modules.reader.domain.ReaderAnnotation;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 阅读批注仓储。
 */
public interface ReaderAnnotationRepository extends JpaRepository<ReaderAnnotation, UUID> {

    List<ReaderAnnotation> findByOwnerUserIdAndReaderItemIdOrderByCreatedAtDesc(UUID ownerUserId, UUID readerItemId);

    Optional<ReaderAnnotation> findByOwnerUserIdAndReaderItemIdAndClientOperationId(
            UUID ownerUserId,
            UUID readerItemId,
            String clientOperationId
    );

    void deleteByOwnerUserIdAndId(UUID ownerUserId, UUID id);

    void deleteByOwnerUserIdAndReaderItemIdIn(UUID ownerUserId, Collection<UUID> readerItemIds);

    void deleteByReaderItemIdIn(Collection<UUID> readerItemIds);
}
