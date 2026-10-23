package com.omninest.modules.search.service;

import com.omninest.modules.search.repository.SearchIndexStateRepository;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 搜索模块的用户删除清理：索引状态行与个人索引目录。
 *
 * <p>File Feature 的用户清理端口只依赖该服务，不直接访问 Search 仓储，
 * 避免跨 Feature 的 repository 依赖。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class SearchIndexUserPurgeService {

    private final SearchIndexStateRepository searchIndexStateRepository;
    private final FileSearchIndexService fileSearchIndexService;

    /**
     * 清理指定用户的搜索索引状态与目录。
     *
     * @param userId 用户 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void purgeUser(UUID userId) {
        searchIndexStateRepository.deleteByOwnerUserId(userId);
        // 索引目录属于可重建派生数据，删除失败只留告警，不阻塞用户删除事务。
        fileSearchIndexService.deleteUserIndex(userId);
        log.info("已清理用户搜索索引: userId={}", userId);
    }
}
