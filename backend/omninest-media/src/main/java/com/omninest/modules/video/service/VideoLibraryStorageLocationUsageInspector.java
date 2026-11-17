package com.omninest.modules.video.service;

import com.omninest.modules.file.service.StorageLocationUsageInspector;
import com.omninest.modules.video.repository.VideoLibrarySourceRepository;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 检查存储位置是否仍被影视库来源引用。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class VideoLibraryStorageLocationUsageInspector implements StorageLocationUsageInspector {

    private final VideoLibrarySourceRepository sourceRepository;

    /**
     * 判断存储位置是否关联任意影视库来源。
     *
     * @param storageLocationId 存储位置 ID
     * @return 存在影视库来源时返回 true
     */
    @Override
    @Transactional(readOnly = true)
    public boolean isInUse(UUID storageLocationId) {
        return sourceRepository.countByStorageLocationId(storageLocationId) > 0;
    }
}
