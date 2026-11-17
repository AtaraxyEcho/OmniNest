package com.omninest.modules.music.repository;

import com.omninest.modules.music.domain.MusicScanJob;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface MusicScanJobRepository extends JpaRepository<MusicScanJob, UUID> {
    Optional<MusicScanJob> findByIdAndOwnerUserId(UUID id, UUID ownerUserId);

    List<MusicScanJob> findTop20ByOwnerUserIdOrderByCreatedAtDesc(UUID ownerUserId);
}