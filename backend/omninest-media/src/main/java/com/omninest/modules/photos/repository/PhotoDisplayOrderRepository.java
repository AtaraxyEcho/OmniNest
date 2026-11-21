package com.omninest.modules.photos.repository;

import com.omninest.modules.photos.domain.PhotoDisplayOrder;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * 照片多视图自定义排序仓储接口。
 */
public interface PhotoDisplayOrderRepository extends JpaRepository<PhotoDisplayOrder, UUID> {

    List<PhotoDisplayOrder> findByOwnerUserId(UUID ownerUserId);

    Optional<PhotoDisplayOrder> findByOwnerUserIdAndContextKey(UUID ownerUserId, String contextKey);

    void deleteByOwnerUserIdAndContextKey(UUID ownerUserId, String contextKey);
}
