package com.omninest.modules.file.service;

import com.omninest.common.user.UserDataPurgePort;
import com.omninest.modules.file.repository.FileNodePermissionRepository;
import com.omninest.modules.file.repository.FileShareRecipientRepository;
import com.omninest.modules.search.service.SearchIndexUserPurgeService;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件模块的用户删除清理：授权绑定与分享接收关系。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileUserDataPurgeService implements UserDataPurgePort {

    private final FileNodePermissionRepository fileNodePermissionRepository;
    private final FileShareRecipientRepository fileShareRecipientRepository;
    private final SearchIndexUserPurgeService searchIndexUserPurgeService;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void purgeUserData(UUID userId) {
        fileNodePermissionRepository.deleteByGranteeUserId(userId);
        fileShareRecipientRepository.deleteByRecipientUserId(userId);
        searchIndexUserPurgeService.purgeUser(userId);
        log.info("已清理文件模块用户关联数据: userId={}", userId);
    }
}
