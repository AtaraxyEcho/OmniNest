package com.omninest.modules.search.service;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.search.event.FileIndexUserPurgeEvent;
import com.omninest.modules.search.repository.SearchIndexStateRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

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
    private final TaskDispatchService taskDispatchService;

    /**
     * 删除指定用户的搜索索引状态行，并投递目录物理清理事件。
     *
     * <p>物理目录由 Worker 独占写入并缓存 {@code IndexWriter}，请求进程直接删盘会与
     * 其它进程抢写锁或留下悬空句柄。这里只删数据库行并投递清理事件；事务提交后
     * 立即立跨进程墓碑并释放本进程 writer，Worker 再删目录。</p>
     *
     * @param userId 用户 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void purgeUser(UUID userId) {
        searchIndexStateRepository.deleteByOwnerUserId(userId);
        taskDispatchService.enqueue(
                userId,
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_INDEX_USER_PURGE_ROUTING_KEY,
                new FileIndexUserPurgeEvent(userId)
        );
        markPurgedAfterCommit(userId);
        log.info("已提交用户搜索索引清理: userId={}", userId);
    }

    private void markPurgedAfterCommit(UUID userId) {
        Runnable mark = () -> fileSearchIndexService.markUserPurged(userId);
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            mark.run();
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                mark.run();
            }
        });
    }

    /**
     * 在持有索引目录写锁的 Worker 进程内删除用户索引目录。
     *
     * @param userId 用户 ID
     * @return 目录删除成功时返回 true
     */
    public boolean purgePhysicalIndex(UUID userId) {
        return fileSearchIndexService.deleteUserIndex(userId);
    }
}
