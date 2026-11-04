package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.UploadStatus;
import com.omninest.modules.file.dto.FileUploadQueueItemDto;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;

/**
 * 上传队列投影测试。
 *
 * <p>客户端要按「原会话的位置」重新提交一个已过期的上传，必须知道会话属于个人空间还是共享空间；
 * 队列投影漏掉 {@code spaceType} 时，重启只能落回用户此刻浏览的目录，把文件传到另一个空间。
 */
class FileUploadQueueServiceTest {

    private final FileUploadSessionRepository sessionRepository = mock(FileUploadSessionRepository.class);
    private final FileUploadQueueService service = new FileUploadQueueService(sessionRepository);

    @Test
    void queueItemCarriesSpaceAndParentForRestartTarget() {
        UUID parentId = UUID.randomUUID();
        FileUploadSession session = new FileUploadSession();
        session.setId(UUID.randomUUID());
        session.setUploadId("upload-1");
        session.setTargetParentId(parentId);
        session.setFileName("spring-raw.mov");
        session.setTotalSizeBytes(1_200);
        session.setPartSizeBytes(120);
        session.setTotalParts(10);
        session.setUploadedParts(4);
        session.setStatus(UploadStatus.EXPIRED.getValue());
        session.setSpaceType(SpaceType.SHARED);
        session.setExpiresAt(Instant.parse("2026-11-04T00:00:00Z"));
        session.setUpdatedAt(Instant.parse("2026-11-03T00:00:00Z"));
        when(sessionRepository.findByOwnerUserId(any(), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(session)));

        Page<FileUploadQueueItemDto> page = service.listUploadQueue(UUID.randomUUID(), 0, 20);

        assertThat(page.getContent()).hasSize(1);
        FileUploadQueueItemDto item = page.getContent().getFirst();
        assertThat(item.uploadId()).isEqualTo("upload-1");
        assertThat(item.status()).isEqualTo(UploadStatus.EXPIRED.getValue());
        assertThat(item.spaceType()).isEqualTo(SpaceType.SHARED.getValue());
        assertThat(item.parentId()).isEqualTo(parentId);
    }

    @Test
    void queueItemDefaultsToPersonalSpaceWhenSessionIsPersonal() {
        FileUploadSession session = new FileUploadSession();
        session.setId(UUID.randomUUID());
        session.setUploadId("upload-2");
        session.setFileName("notes.txt");
        session.setStatus(UploadStatus.UPLOADING.getValue());
        session.setSpaceType(SpaceType.PERSONAL);
        session.setExpiresAt(Instant.parse("2026-11-05T00:00:00Z"));
        session.setUpdatedAt(Instant.parse("2026-11-04T00:00:00Z"));
        when(sessionRepository.findByOwnerUserId(any(), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(session)));

        FileUploadQueueItemDto item =
                service.listUploadQueue(UUID.randomUUID(), 0, 20).getContent().getFirst();

        assertThat(item.spaceType()).isEqualTo(SpaceType.PERSONAL.getValue());
        assertThat(item.parentId()).isNull();
    }
}
