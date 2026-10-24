package com.omninest.modules.search.service;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.search.event.FileIndexUserPurgeEvent;
import com.omninest.modules.search.repository.SearchIndexStateRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 用户搜索索引清理服务测试：数据库行同步删除、目录清理必须投递 Worker。
 */
class SearchIndexUserPurgeServiceTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final SearchIndexStateRepository stateRepository = mock(SearchIndexStateRepository.class);
    private final FileSearchIndexService fileSearchIndexService = mock(FileSearchIndexService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final SearchIndexUserPurgeService service = new SearchIndexUserPurgeService(
            stateRepository, fileSearchIndexService, taskDispatchService);

    @Test
    void purgeUserDeletesStateAndDispatchesWorkerCleanup() {
        service.purgeUser(USER_ID);

        verify(stateRepository).deleteByOwnerUserId(USER_ID);
        verify(fileSearchIndexService).markUserPurged(USER_ID);
        verify(taskDispatchService).enqueue(
                USER_ID,
                QueueNames.TASK_EXCHANGE,
                QueueNames.FILE_INDEX_USER_PURGE_ROUTING_KEY,
                new FileIndexUserPurgeEvent(USER_ID)
        );
    }

    @Test
    void purgePhysicalIndexDeletesDirectoryInWorkerProcess() {
        service.purgePhysicalIndex(USER_ID);

        verify(fileSearchIndexService).deleteUserIndex(USER_ID);
    }
}
