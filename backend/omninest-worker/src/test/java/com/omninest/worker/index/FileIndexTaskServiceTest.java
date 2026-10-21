package com.omninest.worker.index;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.search.service.FileSearchIndexService;
import java.time.Instant;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 文件索引任务测试。
 *
 * @author OmniNest
 */
class FileIndexTaskServiceTest {
    private final FileSearchIndexService fileSearchIndexService = Mockito.mock(FileSearchIndexService.class);
    private final FileLifecycleGuard fileLifecycleGuard = Mockito.mock(FileLifecycleGuard.class);
    private final FileIndexTaskService service = new FileIndexTaskService(
            fileSearchIndexService,
            fileLifecycleGuard
    );

    @Test
    void processIndexesPersonalFile() {
        FileUploadedEvent event = event();
        FileDescriptor descriptor = descriptor(SpaceType.PERSONAL);
        Mockito.when(fileLifecycleGuard.requireOwnedWritable(event.ownerUserId(), event.fileNodeId()))
                .thenReturn(descriptor);

        service.process(event);

        Mockito.verify(fileSearchIndexService).indexFile(
                event.fileNodeId(),
                event.ownerUserId(),
                event.fileName(),
                null,
                SpaceType.PERSONAL.getValue()
        );
    }

    @Test
    void processIndexesSharedFile() {
        FileUploadedEvent event = event();
        FileDescriptor descriptor = descriptor(SpaceType.SHARED);
        Mockito.when(fileLifecycleGuard.requireOwnedWritable(event.ownerUserId(), event.fileNodeId()))
                .thenReturn(descriptor);

        service.process(event);

        Mockito.verify(fileSearchIndexService).indexFile(
                event.fileNodeId(),
                event.ownerUserId(),
                event.fileName(),
                null,
                SpaceType.SHARED.getValue()
        );
    }

    @Test
    void processMissingFileStopsBeforeIndex() {
        FileUploadedEvent event = event();
        Mockito.when(fileLifecycleGuard.requireOwnedWritable(event.ownerUserId(), event.fileNodeId()))
                .thenThrow(new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));

        Assertions.assertThatThrownBy(() -> service.process(event))
                .isInstanceOf(BusinessException.class);

        Mockito.verifyNoInteractions(fileSearchIndexService);
    }

    private FileDescriptor descriptor(SpaceType spaceType) {
        FileDescriptor descriptor = Mockito.mock(FileDescriptor.class);
        Mockito.when(descriptor.spaceType()).thenReturn(spaceType);
        return descriptor;
    }

    private FileUploadedEvent event() {
        return new FileUploadedEvent(
                UUID.randomUUID(),
                UUID.randomUUID(),
                UUID.randomUUID(),
                "test-bucket",
                "test-object-key",
                "test-file.pdf",
                "application/pdf",
                1024L,
                Instant.now()
        );
    }
}
