package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.alibaba.fastjson2.JSON;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.dto.FileObjectDescriptor;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.config.PhotoBatchDownloadProperties;
import com.omninest.modules.photos.domain.PhotoBatchTask;
import com.omninest.modules.photos.domain.PhotoItem;
import com.omninest.modules.photos.domain.PhotoTag;
import com.omninest.modules.photos.dto.PhotoDtos;
import com.omninest.modules.photos.event.PhotoBatchEvent;
import com.omninest.modules.photos.repository.PhotoBatchTaskRepository;
import com.omninest.modules.photos.repository.PhotoItemRepository;
import com.omninest.modules.photos.repository.PhotoTagRepository;
import com.omninest.common.messaging.QueueNames;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;
import org.mockito.ArgumentCaptor;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 照片批量下载临时文件测试。
 *
 * @author OmniNest
 */
class PhotoBatchServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID TASK_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID PHOTO_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID FILE_OBJECT_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");
    private static final UUID ZIP_FILE_ID = UUID.fromString("60000000-0000-0000-0000-000000000001");

    private final PhotoBatchTaskRepository batchTaskRepository = mock(PhotoBatchTaskRepository.class);
    private final PhotoItemRepository photoItemRepository = mock(PhotoItemRepository.class);
    private final PhotoTagRepository photoTagRepository = mock(PhotoTagRepository.class);
    private final PhotoAlbumService albumService = mock(PhotoAlbumService.class);
    private final TaskDispatchService taskDispatchService = mock(TaskDispatchService.class);
    private final FileMetadataQueryService fileMetadataQueryService = mock(FileMetadataQueryService.class);
    private final DerivedAssetStorageService derivedAssetStorageService = mock(DerivedAssetStorageService.class);
    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final TaskRecordService taskRecordService = mock(TaskRecordService.class);
    private final MediaSyncEventService syncEventService = mock(MediaSyncEventService.class);
    private final PhotoBatchDownloadProperties downloadProperties = new PhotoBatchDownloadProperties();
    private final TransactionTemplate transactionTemplate = mock(TransactionTemplate.class);
    private final PhotoBatchService service = new PhotoBatchService(
            batchTaskRepository,
            photoItemRepository,
            photoTagRepository,
            albumService,
            taskDispatchService,
            fileMetadataQueryService,
            derivedAssetStorageService,
            fileQueryService,
            taskRecordService,
            syncEventService,
            downloadProperties,
            transactionTemplate
    );

    @BeforeEach
    void setUpTaskClaim() {
        when(taskRecordService.claimForExecution(any(UUID.class), any(String.class))).thenReturn(true);
    }

    @Test
    void createBatchTaskEnqueuesThroughOutbox() {
        when(batchTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        service.createBatchTask(
                OWNER_ID,
                new PhotoDtos.CreateBatchTaskRequest("TAG", List.of(PHOTO_ID), null));

        ArgumentCaptor<PhotoBatchEvent> eventCaptor = ArgumentCaptor.forClass(PhotoBatchEvent.class);
        verify(taskDispatchService).enqueue(
                any(UUID.class),
                eq(QueueNames.TASK_EXCHANGE),
                eq(QueueNames.PHOTO_BATCH_ROUTING_KEY),
                eventCaptor.capture()
        );
        assertThat(eventCaptor.getValue().ownerUserId()).isEqualTo(OWNER_ID);
        verify(taskRecordService).createQueuedTask(
                any(UUID.class), eq(OWNER_ID), eq("PHOTO_BATCH_TAG"), any(), any());
    }

    @Test
    void executeTagTaskPublishesSyncEventAfterMutation() {
        PhotoBatchTask task = new PhotoBatchTask();
        task.setId(TASK_ID);
        task.setTaskId(TASK_ID);
        task.setOwnerUserId(OWNER_ID);
        task.setTaskType("TAG");
        task.setTotalItems(1);
        task.setParams(JSON.toJSONString(
                Map.of("photoIds", List.of(PHOTO_ID.toString()), "tag", "holiday")));

        when(batchTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        when(batchTaskRepository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(photoTagRepository.findByOwnerUserIdAndPhotoIdIn(OWNER_ID, List.of(PHOTO_ID)))
                .thenReturn(List.of());
        when(photoTagRepository.saveAll(any())).thenAnswer(invocation -> invocation.getArgument(0));
        doAnswer(invocation -> {
            Consumer<TransactionStatus> action = invocation.getArgument(0);
            action.accept(null);
            return null;
        }).when(transactionTemplate).executeWithoutResult(any());

        service.executeBatchTask(TASK_ID, OWNER_ID);

        verify(syncEventService).record(
                eq(OWNER_ID),
                eq(SyncScope.PHOTOS),
                eq("PHOTO_BATCH"),
                isNull(),
                eq(SyncAction.UPDATED),
                isNull(),
                eq(Map.of()));
        verify(taskRecordService).markCompleted(eq(TASK_ID), any(Map.class));
    }

    @Test
    void executeDownloadTaskWritesZipToFileAndDeletesTemporaryFile() throws Exception {
        PhotoBatchTask task = downloadTask();
        PhotoItem photo = photo();
        FileDescriptor fileNode = fileNode();
        FileObjectDescriptor fileObject = fileObject();
        byte[] image = "image-data".getBytes(StandardCharsets.UTF_8);
        AtomicReference<Path> uploadedPath = new AtomicReference<>();

        when(batchTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID)).thenReturn(Optional.of(photo));
        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(fileNode));
        when(fileMetadataQueryService.findObjectById(FILE_OBJECT_ID)).thenReturn(Optional.of(fileObject));
        when(fileQueryService.openReadableFileContent(OWNER_ID, FILE_NODE_ID))
                .thenReturn(contentStream(image));
        doAnswer(invocation -> {
            Path zipFile = invocation.getArgument(6);
            uploadedPath.set(zipFile);
            assertThat(Files.isRegularFile(zipFile)).isTrue();
            try (ZipInputStream inputStream = new ZipInputStream(Files.newInputStream(zipFile))) {
                ZipEntry entry = inputStream.getNextEntry();
                assertThat(entry.getName()).isEqualTo("001_holiday.jpg");
                assertThat(inputStream.readAllBytes()).isEqualTo(image);
            }
            return ZIP_FILE_ID;
        }).when(derivedAssetStorageService).store(
                eq(OWNER_ID),
                eq("PHOTO_BATCH"),
                eq(TASK_ID),
                eq("DOWNLOAD"),
                anyString(),
                eq("application/zip"),
                any(Path.class)
        );

        service.executeBatchTask(TASK_ID, OWNER_ID);

        assertThat(task.getStatus()).isEqualTo("COMPLETED");
        assertThat(task.getResult()).isEqualTo(ZIP_FILE_ID.toString());
        assertThat(uploadedPath.get()).isNotNull();
        assertThat(Files.exists(uploadedPath.get())).isFalse();
        verify(taskRecordService).markCompleted(eq(TASK_ID), any(Map.class));
    }

    @Test
    void executeDownloadTaskStreamsLargeSourceWithBoundedReads() throws Exception {
        int sourceBytes = 64 * 1024 * 1024;
        PhotoBatchTask task = downloadTask();
        GuardedGeneratedInputStream source = new GuardedGeneratedInputStream(sourceBytes);
        AtomicReference<Path> uploadedPath = new AtomicReference<>();
        FileObjectDescriptor fileObject = new FileObjectDescriptor(
                FILE_OBJECT_ID,
                "user-files",
                "photos/photo.jpg",
                null,
                sourceBytes,
                "image/jpeg"
        );

        when(batchTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID)).thenReturn(Optional.of(photo()));
        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(fileNode()));
        when(fileMetadataQueryService.findObjectById(FILE_OBJECT_ID)).thenReturn(Optional.of(fileObject));
        when(fileQueryService.openReadableFileContent(OWNER_ID, FILE_NODE_ID))
                .thenReturn(
                        new FileContentStream(source, "photo.jpg", sourceBytes, "image/jpeg"));
        when(derivedAssetStorageService.store(
                eq(OWNER_ID),
                eq("PHOTO_BATCH"),
                eq(TASK_ID),
                eq("DOWNLOAD"),
                anyString(),
                eq("application/zip"),
                any(Path.class)
        )).thenAnswer(invocation -> {
            Path archive = invocation.getArgument(6);
            uploadedPath.set(archive);
            assertThat(Files.size(archive)).isPositive();
            return ZIP_FILE_ID;
        });

        service.executeBatchTask(TASK_ID, OWNER_ID);

        assertThat(task.getStatus()).isEqualTo("COMPLETED");
        assertThat(task.getProcessedItems()).isEqualTo(1);
        assertThat(source.maxRequestedBytes()).isLessThanOrEqualTo(64 * 1024);
        assertThat(uploadedPath.get()).isNotNull();
        assertThat(Files.exists(uploadedPath.get())).isFalse();
    }

    @Test
    void executeDownloadTaskRejectsSourceSizeMismatchWithoutPublishingArchive() {
        PhotoBatchTask task = downloadTask();
        when(batchTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID)).thenReturn(Optional.of(photo()));
        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(fileNode()));
        when(fileMetadataQueryService.findObjectById(FILE_OBJECT_ID)).thenReturn(Optional.of(fileObject()));
        when(fileQueryService.openReadableFileContent(OWNER_ID, FILE_NODE_ID))
                .thenReturn(contentStream(new byte[]{1, 2, 3}));

        service.executeBatchTask(TASK_ID, OWNER_ID);

        assertThat(task.getStatus()).isEqualTo("FAILED");
        assertThat(task.getErrorMessage()).contains("大小与元数据不一致");
        verify(derivedAssetStorageService, never()).store(
                eq(OWNER_ID),
                eq("PHOTO_BATCH"),
                eq(TASK_ID),
                eq("DOWNLOAD"),
                anyString(),
                eq("application/zip"),
                any(Path.class)
        );
    }

    @Test
    void executeDownloadTaskRejectsInsufficientTemporaryDiskBeforeReadingSource() {
        PhotoBatchTask task = downloadTask();
        PhotoBatchDownloadProperties constrainedProperties = new PhotoBatchDownloadProperties();
        constrainedProperties.setMinFreeBytes(Long.MAX_VALUE / 2);
        PhotoBatchService constrainedService = createService(constrainedProperties);
        when(batchTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        when(photoItemRepository.findByOwnerUserIdAndId(OWNER_ID, PHOTO_ID)).thenReturn(Optional.of(photo()));
        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(fileNode()));
        when(fileMetadataQueryService.findObjectById(FILE_OBJECT_ID)).thenReturn(Optional.of(fileObject()));

        constrainedService.executeBatchTask(TASK_ID, OWNER_ID);

        assertThat(task.getStatus()).isEqualTo("FAILED");
        assertThat(task.getErrorMessage()).contains("临时磁盘空间不足");
        verify(fileQueryService, never()).openReadableFileContent(any(UUID.class), any(UUID.class));
        verify(derivedAssetStorageService, never()).store(
                eq(OWNER_ID),
                eq("PHOTO_BATCH"),
                eq(TASK_ID),
                eq("DOWNLOAD"),
                anyString(),
                eq("application/zip"),
                any(Path.class)
        );
    }

    @Test
    void resolveDownloadTicketReturnsSizeDigestAndExpiry() {
        PhotoBatchTask task = downloadTask();
        task.setStatus("COMPLETED");
        task.setResult(ZIP_FILE_ID.toString());
        FileDescriptor archiveNode = new FileDescriptor(
                ZIP_FILE_ID,
                OWNER_ID,
                null,
                "FILE",
                "photos.zip",
                "/.metadata/PHOTO_BATCH/task/DOWNLOAD/photos.zip",
                "application/zip",
                123,
                FILE_OBJECT_ID,
                "DERIVED",
                false,
                false,
                SpaceType.PERSONAL,
                OWNER_ID,
                null,
                null
        );
        FileObjectDescriptor archiveObject = new FileObjectDescriptor(
                FILE_OBJECT_ID,
                "derived-assets",
                "derived/photos.zip",
                "abc123",
                123,
                "application/zip"
        );
        Instant expiresAt = Instant.parse("2026-07-27T00:00:00Z");
        when(batchTaskRepository.findByIdAndOwnerUserId(TASK_ID, OWNER_ID)).thenReturn(Optional.of(task));
        when(fileMetadataQueryService.findById(ZIP_FILE_ID)).thenReturn(Optional.of(archiveNode));
        when(fileMetadataQueryService.findObjectById(FILE_OBJECT_ID)).thenReturn(Optional.of(archiveObject));
        when(fileQueryService.createDownloadUrl(OWNER_ID, ZIP_FILE_ID)).thenReturn(new FileDownloadUrlDto(
                ZIP_FILE_ID,
                "photos.zip",
                "https://storage.example/photos.zip",
                expiresAt
        ));

        var ticket = service.resolveDownloadTicket(OWNER_ID, TASK_ID);

        assertThat(ticket.url()).isEqualTo("https://storage.example/photos.zip");
        assertThat(ticket.fileName()).isEqualTo("photos.zip");
        assertThat(ticket.sizeBytes()).isEqualTo(123);
        assertThat(ticket.sha256()).isEqualTo("abc123");
        assertThat(ticket.expiresAt()).isEqualTo(expiresAt);
    }

    @Test
    void executeTagTaskRunsInsideShortTransaction() {
        PhotoBatchTask task = downloadTask();
        task.setTaskType("TAG");
        task.setParams(JSON.toJSONString(Map.of(
                "photoIds", List.of(PHOTO_ID.toString()),
                "tag", "family"
        )));
        when(batchTaskRepository.findById(TASK_ID)).thenReturn(Optional.of(task));
        when(photoTagRepository.findByOwnerUserIdAndPhotoIdIn(OWNER_ID, List.of(PHOTO_ID)))
                .thenReturn(List.of());
        when(photoTagRepository.saveAll(any())).thenAnswer(invocation -> invocation.getArgument(0));
        doAnswer(invocation -> {
            Consumer<TransactionStatus> action = invocation.getArgument(0);
            action.accept(mock(TransactionStatus.class));
            return null;
        }).when(transactionTemplate).executeWithoutResult(any());

        service.executeBatchTask(TASK_ID, OWNER_ID);

        assertThat(task.getStatus()).isEqualTo("COMPLETED");
        verify(transactionTemplate).executeWithoutResult(any());
        verify(photoTagRepository).saveAll(any());
    }

    private PhotoBatchTask downloadTask() {
        PhotoBatchTask task = new PhotoBatchTask();
        task.setId(TASK_ID);
        task.setTaskId(TASK_ID);
        task.setOwnerUserId(OWNER_ID);
        task.setTaskType("DOWNLOAD");
        task.setTotalItems(1);
        task.setParams(JSON.toJSONString(Map.of("photoIds", List.of(PHOTO_ID.toString()))));
        return task;
    }

    private PhotoBatchService createService(PhotoBatchDownloadProperties properties) {
        return new PhotoBatchService(
                batchTaskRepository,
                photoItemRepository,
                photoTagRepository,
                albumService,
                taskDispatchService,
                fileMetadataQueryService,
                derivedAssetStorageService,
                fileQueryService,
                taskRecordService,
                syncEventService,
                properties,
                transactionTemplate
        );
    }

    private PhotoItem photo() {
        PhotoItem photo = new PhotoItem();
        photo.setId(PHOTO_ID);
        photo.setOwnerUserId(OWNER_ID);
        photo.setFileNodeId(FILE_NODE_ID);
        photo.setTitle("holiday");
        photo.setFormat("jpg");
        return photo;
    }

    private FileDescriptor fileNode() {
        return new FileDescriptor(
                FILE_NODE_ID,
                OWNER_ID,
                null,
                "FILE",
                "photo.jpg",
                "/photo.jpg",
                "image/jpeg",
                10,
                FILE_OBJECT_ID,
                "UPLOAD",
                false,
                false,
                SpaceType.PERSONAL,
                OWNER_ID,
                null,
                null
        );
    }

    private FileObjectDescriptor fileObject() {
        return new FileObjectDescriptor(
                FILE_OBJECT_ID,
                "user-files",
                "photos/photo.jpg",
                null,
                10,
                "image/jpeg"
        );
    }

    private static final class GuardedGeneratedInputStream extends InputStream {
        private int remaining;
        private int maxRequestedBytes;

        private GuardedGeneratedInputStream(int sizeBytes) {
            remaining = sizeBytes;
        }

        @Override
        public int read() {
            if (remaining == 0) {
                return -1;
            }
            remaining--;
            return remaining & 0xff;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) {
            if (remaining == 0) {
                return -1;
            }
            maxRequestedBytes = Math.max(maxRequestedBytes, length);
            int readBytes = Math.min(length, remaining);
            for (int index = 0; index < readBytes; index++) {
                buffer[offset + index] = (byte) ((remaining - index) & 0xff);
            }
            remaining -= readBytes;
            return readBytes;
        }

        @Override
        public byte[] readAllBytes() {
            throw new AssertionError("批量 ZIP 不得将源文件完整读入内存");
        }

        @Override
        public long transferTo(OutputStream output) {
            throw new AssertionError("批量 ZIP 必须使用受控缓冲复制");
        }

        private int maxRequestedBytes() {
            return maxRequestedBytes;
        }
    }

    private FileContentStream contentStream(byte[] data) {
        return new FileContentStream(
                new ByteArrayInputStream(data),
                "photo.jpg",
                data.length,
                "image/jpeg"
        );
    }
}
