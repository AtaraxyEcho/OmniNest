package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.StorageImportTask;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 外部存储导入任务仓库。
 */
public interface StorageImportTaskRepository extends JpaRepository<StorageImportTask, UUID> {
    List<StorageImportTask> findByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId);

    Optional<StorageImportTask> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    List<StorageImportTask> findByStatusIn(List<String> statuses);
}
