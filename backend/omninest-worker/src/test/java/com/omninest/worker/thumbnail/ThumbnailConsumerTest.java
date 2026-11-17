package com.omninest.worker.thumbnail;

import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FilePostProcessingTaskService;
import com.omninest.modules.photos.service.PhotoSourceFileService;
import com.omninest.modules.photos.service.PhotoThumbnailService;
import com.omninest.modules.photos.service.PhotoAdminService;
import com.omninest.worker.file.FilePostProcessingTaskTracker;
import com.rabbitmq.client.Channel;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * ThumbnailConsumer 单元测试。
 * 验证缩略图生成逻辑：图片文件触发生成，已存在缩略图仅回填封面，非图片文件跳过。
 */
@ExtendWith(MockitoExtension.class)
class ThumbnailConsumerTest {

    @Mock
    private PhotoSourceFileService photoSourceFileService;

    @Mock
    private PhotoThumbnailService photoThumbnailService;

    @Mock
    private PhotoAdminService photoAdminService;

    @Mock
    private FileLifecycleGuard fileLifecycleGuard;

    @Mock
    private FilePostProcessingTaskTracker taskTracker;

    @Mock
    private Channel channel;

    @InjectMocks
    private ThumbnailConsumer thumbnailConsumer;

    @BeforeEach
    void allowFileProcessing() {
        lenient().when(fileLifecycleGuard.isOwnedProcessable(any(), any())).thenReturn(true);
        lenient().when(taskTracker.begin(any(), any(), any(), any()))
                .thenReturn(new FilePostProcessingTaskTracker.TrackedTask(UUID.randomUUID(), true));
        lenient().when(photoThumbnailService.findStoredThumbnailFileNodeId(any(), any()))
                .thenReturn(Optional.empty());
    }

    /**
     * 构造测试用的文件上传事件。
     */
    private FileUploadedEvent createEvent(String fileName, String mimeType) {
        return new FileUploadedEvent(
                UUID.randomUUID(),
                UUID.randomUUID(),
                UUID.randomUUID(),
                "test-bucket",
                "test-object-key",
                fileName,
                mimeType,
                2048L,
                Instant.now()
        );
    }

    /**
     * 构造测试用的 RabbitMQ 消息。
     */
    private Message createMessage() {
        MessageProperties props = new MessageProperties();
        props.setDeliveryTag(1L);
        return new Message(new byte[0], props);
    }

    /**
     * 构造真实暂存文件句柄；消费者结束后会删除该临时文件。
     */
    private PhotoSourceFileService.StagedPhotoFile stageJpeg() throws IOException {
        Path temp = Files.createTempFile("thumbnail-consumer-test", ".jpg");
        return new PhotoSourceFileService.StagedPhotoFile(temp, "photo.jpg", 100, "image/jpeg", false);
    }

    @Test
    @DisplayName("JPEG 图片应触发缩略图生成")
    void handle_withJpegImage_shouldGenerateThumbnail() throws IOException {
        FileUploadedEvent event = createEvent("photo.jpg", "image/jpeg");
        UUID thumbnailId = UUID.randomUUID();
        when(photoSourceFileService.stageReadable(any(), any())).thenReturn(stageJpeg());
        when(photoThumbnailService.generateAndStoreFile(
                any(), any(), any(Path.class), any()
        )).thenReturn(thumbnailId);

        thumbnailConsumer.handle(event, createMessage(), channel);

        verify(photoThumbnailService).generateAndStoreFile(
                eq(event.ownerUserId()),
                eq(event.fileNodeId()),
                any(Path.class),
                eq("photo.jpg")
        );
        verify(photoAdminService).attachCoverIfMissing(
                eq(event.ownerUserId()), eq(event.fileNodeId()), eq(thumbnailId));
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("缩略图已存在时应仅回填封面而不重新生成")
    void handle_withStoredThumbnail_shouldAttachOnly() throws IOException {
        FileUploadedEvent event = createEvent("photo.jpg", "image/jpeg");
        UUID storedThumbnailId = UUID.randomUUID();
        when(photoThumbnailService.findStoredThumbnailFileNodeId(
                event.ownerUserId(), event.fileNodeId())).thenReturn(Optional.of(storedThumbnailId));

        thumbnailConsumer.handle(event, createMessage(), channel);

        verify(photoAdminService).attachCoverIfMissing(
                eq(event.ownerUserId()), eq(event.fileNodeId()), eq(storedThumbnailId));
        verify(photoThumbnailService, never()).generateAndStoreFile(
                any(), any(), any(), any()
        );
        verify(photoSourceFileService, never()).stageReadable(any(), any());
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("PNG 图片应触发缩略图生成")
    void handle_withPngImage_shouldGenerateThumbnail() throws IOException {
        FileUploadedEvent event = createEvent("icon.png", "image/png");
        when(photoSourceFileService.stageReadable(any(), any())).thenReturn(stageJpeg());
        when(photoThumbnailService.generateAndStoreFile(
                any(), any(), any(Path.class), any()
        )).thenReturn(UUID.randomUUID());

        thumbnailConsumer.handle(event, createMessage(), channel);

        verify(photoThumbnailService).generateAndStoreFile(
                eq(event.ownerUserId()),
                eq(event.fileNodeId()),
                any(Path.class),
                eq("photo.jpg")
        );
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("WebP 图片应跳过缩略图生成")
    void handle_withWebpImage_shouldSkip() throws IOException {
        FileUploadedEvent event = createEvent("avatar.webp", "image/webp");

        thumbnailConsumer.handle(event, createMessage(), channel);

        verify(photoThumbnailService, never()).generateAndStoreFile(
                any(), any(), any(), any()
        );
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("PDF 文件不应触发缩略图生成")
    void handle_withPdfFile_shouldSkip() throws IOException {
        FileUploadedEvent event = createEvent("doc.pdf", "application/pdf");

        thumbnailConsumer.handle(event, createMessage(), channel);

        verify(photoThumbnailService, never()).generateAndStoreFile(
                any(), any(), any(), any()
        );
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("文本文件不应触发缩略图生成")
    void handle_withTextFile_shouldSkip() throws IOException {
        FileUploadedEvent event = createEvent("readme.txt", "text/plain");

        thumbnailConsumer.handle(event, createMessage(), channel);

        verify(photoThumbnailService, never()).generateAndStoreFile(
                any(), any(), any(), any()
        );
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("mimeType 为 null 时不应触发缩略图生成")
    void handle_withNullMimeType_shouldSkip() throws IOException {
        FileUploadedEvent event = createEvent("unknown", null);

        thumbnailConsumer.handle(event, createMessage(), channel);

        verify(photoThumbnailService, never()).generateAndStoreFile(
                any(), any(), any(), any()
        );
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("缩略图服务返回 null 时不抛异常")
    void handle_whenThumbnailServiceReturnsNull_shouldCompleteNormally() throws IOException {
        FileUploadedEvent event = createEvent("photo.jpg", "image/jpeg");
        when(photoSourceFileService.stageReadable(any(), any())).thenReturn(stageJpeg());
        when(photoThumbnailService.generateAndStoreFile(
                any(), any(), any(Path.class), any()
        )).thenReturn(null);

        thumbnailConsumer.handle(event, createMessage(), channel);

        verify(photoThumbnailService).generateAndStoreFile(
                eq(event.ownerUserId()),
                eq(event.fileNodeId()),
                any(Path.class),
                eq("photo.jpg")
        );
        verify(photoAdminService, never()).attachCoverIfMissing(
                any(), any(), any());
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("暂存或生成抛出异常时应记录失败并 ack 消息")
    void handle_whenStagingThrows_shouldHandleFailureAndAck() throws IOException {
        FileUploadedEvent event = createEvent("photo.jpg", "image/jpeg");
        when(photoSourceFileService.stageReadable(any(), any()))
                .thenThrow(new RuntimeException("存储服务不可用"));

        thumbnailConsumer.handle(event, createMessage(), channel);

        verify(photoThumbnailService, never()).generateAndStoreFile(
                any(), any(), any(), any()
        );
        verify(taskTracker).handleFailure(
                eq("THUMBNAIL"), any(), any(), eq(event), any());
        verify(channel).basicAck(1L, false);
    }
}
