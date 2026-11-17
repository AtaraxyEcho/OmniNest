package com.omninest.modules.video.service;

import com.omninest.common.user.UserDataPurgePort;
import com.omninest.modules.video.repository.MediaLibraryAccessRepository;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 媒体模块的用户删除清理：影视库成员授权。
 *
 * <p>照片检索已收敛到数据库，用户删除只依赖行级清理，不再需要跨进程清理索引卷。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MediaUserDataPurgeService implements UserDataPurgePort {

    private final MediaLibraryAccessRepository mediaLibraryAccessRepository;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void purgeUserData(UUID userId) {
        mediaLibraryAccessRepository.deleteByUserId(userId);
        log.info("已清理媒体库用户授权: userId={}", userId);
    }
}
