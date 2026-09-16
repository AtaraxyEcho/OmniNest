package com.omninest.worker.tika;

import com.omninest.common.messaging.QueueNames;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.search.service.FileSearchIndexService;
import com.omninest.worker.file.FilePostProcessingTaskTracker;
import com.rabbitmq.client.Channel;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.UUID;
import java.util.zip.CRC32;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Captor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

/**
 * TextExtractionConsumer 单元测试。
 * 验证文本提取流程：从对象存储读取文件 → Tika 提取文本 → 写入索引。
 */
@ExtendWith(MockitoExtension.class)
class TextExtractionConsumerTest {

    @Mock
    private ObjectStorageClient objectStorageClient;

    @Mock
    private FileSearchIndexService fileSearchIndexService;

    @Mock
    private FileLifecycleGuard fileLifecycleGuard;

    @Mock
    private FilePostProcessingTaskTracker taskTracker;

    @Mock
    private Channel channel;

    @InjectMocks
    private TextExtractionConsumer textExtractionConsumer;

    @Captor
    private ArgumentCaptor<String> textCaptor;

    @BeforeEach
    void allowFileProcessing() {
        when(fileLifecycleGuard.isOwnedProcessable(any(), any())).thenReturn(true);
        lenient().when(taskTracker.begin(any(), anyString(), any(), anyString()))
                .thenReturn(new FilePostProcessingTaskTracker.TrackedTask(UUID.randomUUID(), true));
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
                1024L,
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

    @Test
    @DisplayName("成功提取文本后应调用索引服务写入")
    void handle_withExtractableText_shouldCallIndexService() throws IOException {
        FileUploadedEvent event = createEvent("readme.txt", "text/plain");
        // 使用包含纯文本内容的输入流，Tika 可以直接提取
        String fileContent = "这是一段可以提取的中文文本内容用于测试";
        InputStream inputStream = new ByteArrayInputStream(fileContent.getBytes());
        when(objectStorageClient.getObject(any(ObjectStorageKey.class))).thenReturn(inputStream);

        textExtractionConsumer.handle(event, createMessage(), channel);

        verify(fileSearchIndexService).indexFile(
                eq(event.fileNodeId()),
                eq(event.ownerUserId()),
                eq(event.fileName()),
                textCaptor.capture()
        );
        // Tika 的 BodyContentHandler 会在末尾追加换行符，使用 trim 比较
        assertThat(textCaptor.getValue()).startsWith(fileContent);
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("超过写入上限时按已提取片段完成索引而不触发失败重试")
    void handle_whenWriteLimitReached_shouldIndexPartialTextAndComplete() throws IOException {
        FileUploadedEvent event = createEvent("long-novel.epub", "application/epub+zip");
        // 远超默认上限的纯文本，触发 BodyContentHandler 写入上限。
        String longText = "长".repeat(2_100_000);
        InputStream inputStream = new ByteArrayInputStream(longText.getBytes(StandardCharsets.UTF_8));
        when(objectStorageClient.getObject(any(ObjectStorageKey.class))).thenReturn(inputStream);

        textExtractionConsumer.handle(event, createMessage(), channel);

        verify(fileSearchIndexService).indexFile(
                eq(event.fileNodeId()),
                eq(event.ownerUserId()),
                eq(event.fileName()),
                textCaptor.capture()
        );
        assertThat(textCaptor.getValue().length()).isGreaterThan(500_000);
        verify(taskTracker).complete(any(), any());
        verify(taskTracker, never()).handleFailure(any(), any(), any(), any(), any());
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("对象存储抛出异常时经任务跟踪器失败处理且不调用索引服务")
    void handle_whenStorageThrows_shouldNotCallIndexService() throws IOException {
        FileUploadedEvent event = createEvent("broken.pdf", "application/pdf");
        when(objectStorageClient.getObject(any(ObjectStorageKey.class)))
                .thenThrow(new RuntimeException("MinIO 连接失败"));

        textExtractionConsumer.handle(event, createMessage(), channel);

        verify(fileSearchIndexService, never()).indexFile(
                any(), any(), any(), any()
        );
        verify(taskTracker).handleFailure(
                eq("TEXT_EXTRACTION"),
                eq(QueueNames.TEXT_EXTRACTION_ROUTING_KEY),
                any(),
                eq(event),
                any()
        );
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("解析失败时经任务跟踪器失败处理且不调用索引服务")
    void handle_withBlankExtractedText_shouldNotCallIndexService() throws IOException {
        FileUploadedEvent event = createEvent("empty.pdf", "application/pdf");
        // 空输入流无法解析出文本内容，触发异常并进入跟踪器失败处理
        InputStream emptyStream = new ByteArrayInputStream(new byte[0]);
        when(objectStorageClient.getObject(any(ObjectStorageKey.class))).thenReturn(emptyStream);

        textExtractionConsumer.handle(event, createMessage(), channel);

        verify(fileSearchIndexService, never()).indexFile(
                any(), any(), any(), any()
        );
        verify(taskTracker).handleFailure(
                eq("TEXT_EXTRACTION"),
                eq(QueueNames.TEXT_EXTRACTION_ROUTING_KEY),
                any(),
                eq(event),
                any()
        );
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("应使用事件中的 bucket 和 objectKey 构建存储键")
    void handle_shouldConstructCorrectStorageKey() throws IOException {
        String bucket = "user-files";
        String objectKey = "2024/01/doc.txt";
        FileUploadedEvent event = new FileUploadedEvent(
                UUID.randomUUID(),
                UUID.randomUUID(),
                UUID.randomUUID(),
                bucket,
                objectKey,
                "doc.txt",
                "text/plain",
                512L,
                Instant.now()
        );
        InputStream inputStream = new ByteArrayInputStream("文档内容".getBytes());
        when(objectStorageClient.getObject(any(ObjectStorageKey.class))).thenReturn(inputStream);

        textExtractionConsumer.handle(event, createMessage(), channel);

        verify(objectStorageClient).getObject(any(ObjectStorageKey.class));
        verify(channel).basicAck(1L, false);
    }

    @Test
    @DisplayName("EPUB 内嵌 TTF 字体时应正常提取文本而不中断解析")
    void handle_withEpubContainingEmbeddedFont_shouldExtractText() throws IOException {
        FileUploadedEvent event = createEvent("sample.epub", "application/epub+zip");
        byte[] epubBytes = buildEpubWithEmbeddedFont(loadEmbeddedFontBytes());
        when(objectStorageClient.getObject(any(ObjectStorageKey.class)))
                .thenReturn(new ByteArrayInputStream(epubBytes));

        textExtractionConsumer.handle(event, createMessage(), channel);

        verify(fileSearchIndexService).indexFile(
                eq(event.fileNodeId()),
                eq(event.ownerUserId()),
                eq(event.fileName()),
                textCaptor.capture()
        );
        assertThat(textCaptor.getValue()).contains("内嵌字体文本提取回归测试内容");
        verify(channel).basicAck(1L, false);
    }

    /**
     * 读取测试资源中的真实 TTF 字体（仓库前端自带的 OFL 字体副本），
     * 保证内嵌字体可被 FontBox 完整解析，覆盖 Tika 与 FontBox 版本不匹配的历史缺陷。
     */
    private byte[] loadEmbeddedFontBytes() throws IOException {
        try (InputStream fontStream = getClass().getResourceAsStream("/fonts/InstrumentSerif-Regular.ttf")) {
            if (fontStream == null) {
                throw new IOException("测试字体资源缺失: /fonts/InstrumentSerif-Regular.ttf");
            }
            return fontStream.readAllBytes();
        }
    }

    /**
     * 构造内嵌 TTF 字体的最小 EPUB（mimetype 首条目 + container + opf + 章节 + 字体）。
     */
    private byte[] buildEpubWithEmbeddedFont(byte[] fontBytes) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(buffer)) {
            byte[] mimetypeBytes = "application/epub+zip".getBytes(StandardCharsets.US_ASCII);
            ZipEntry mimetype = new ZipEntry("mimetype");
            mimetype.setMethod(ZipEntry.STORED);
            mimetype.setSize(mimetypeBytes.length);
            CRC32 crc = new CRC32();
            crc.update(mimetypeBytes);
            mimetype.setCrc(crc.getValue());
            zip.putNextEntry(mimetype);
            zip.write(mimetypeBytes);
            zip.closeEntry();

            putTextEntry(zip, "META-INF/container.xml", """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                      <rootfiles>
                        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
                      </rootfiles>
                    </container>
                    """);
            putTextEntry(zip, "OEBPS/content.opf", """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="2.0">
                      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                        <dc:title>font-embedded-regression</dc:title>
                        <dc:identifier id="bookid">urn:uuid:00000000-0000-0000-0000-000000000001</dc:identifier>
                        <dc:language>zh</dc:language>
                      </metadata>
                      <manifest>
                        <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
                        <item id="embedded-font" href="fonts/InstrumentSerif-Regular.ttf" media-type="font/ttf"/>
                      </manifest>
                      <spine>
                        <itemref idref="chapter1"/>
                      </spine>
                    </package>
                    """);
            putTextEntry(zip, "OEBPS/chapter1.xhtml", """
                    <?xml version="1.0" encoding="UTF-8"?>
                    <html xmlns="http://www.w3.org/1999/xhtml">
                      <head><title>chapter</title></head>
                      <body><p>内嵌字体文本提取回归测试内容</p></body>
                    </html>
                    """);

            ZipEntry fontEntry = new ZipEntry("OEBPS/fonts/InstrumentSerif-Regular.ttf");
            fontEntry.setSize(fontBytes.length);
            CRC32 fontCrc = new CRC32();
            fontCrc.update(fontBytes);
            fontEntry.setCrc(fontCrc.getValue());
            zip.putNextEntry(fontEntry);
            zip.write(fontBytes);
            zip.closeEntry();
        }
        return buffer.toByteArray();
    }

    /**
     * 向 EPUB 压缩包写入一个 UTF-8 文本条目。
     */
    private void putTextEntry(ZipOutputStream zip, String entryName, String content) throws IOException {
        zip.putNextEntry(new ZipEntry(entryName));
        zip.write(content.getBytes(StandardCharsets.UTF_8));
        zip.closeEntry();
    }

    @Test
    @DisplayName("应正确传递 fileNodeId 和 ownerUserId 到索引服务")
    void handle_shouldPassCorrectIdsToIndexService() throws IOException {
        UUID fileNodeId = UUID.randomUUID();
        UUID ownerUserId = UUID.randomUUID();
        FileUploadedEvent event = new FileUploadedEvent(
                fileNodeId,
                UUID.randomUUID(),
                ownerUserId,
                "bucket",
                "key",
                "notes.txt",
                "text/plain",
                256L,
                Instant.now()
        );
        InputStream inputStream = new ByteArrayInputStream("some text content".getBytes());
        when(objectStorageClient.getObject(any(ObjectStorageKey.class))).thenReturn(inputStream);

        textExtractionConsumer.handle(event, createMessage(), channel);

        verify(fileSearchIndexService).indexFile(
                eq(fileNodeId),
                eq(ownerUserId),
                eq("notes.txt"),
                textCaptor.capture()
        );
        // Tika 的 BodyContentHandler 会在末尾追加换行符，使用 trim 比较
        assertThat(textCaptor.getValue().trim()).isEqualTo("some text content");
        verify(channel).basicAck(1L, false);
    }
}
