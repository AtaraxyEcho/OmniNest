package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.reader.domain.ReaderItem;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 阅读自动导入服务单元测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderAutoImportServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    @Mock
    private ReaderImportService importService;

    @Mock
    private ReaderFileDetector fileDetector;

    @Mock
    private ReaderRuntimeConfigService configService;

    @InjectMocks
    private ReaderAutoImportService autoImportService;

    @BeforeEach
    void setUp() {
        when(configService.autoImportEnabled()).thenReturn(true);
    }

    @Test
    void skipsNonReaderFile() {
        when(fileDetector.isReaderFile("video.mp4")).thenReturn(false);

        Optional<UUID> result = autoImportService.importUploadedFile(uploaded("video.mp4", "video/mp4"));

        assertThat(result).isEmpty();
        verify(importService, never()).importFile(any(), any());
    }

    @Test
    void importsEpubFile() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);

        when(fileDetector.isReaderFile("book.epub")).thenReturn(true);
        when(importService.importFile(OWNER_ID, FILE_ID)).thenReturn(item);

        Optional<UUID> result = autoImportService.importUploadedFile(uploaded("book.epub", "application/epub+zip"));

        assertThat(result).contains(ITEM_ID);
        verify(importService).importFile(OWNER_ID, FILE_ID);
    }

    @Test
    void importsTxtFile() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);

        when(fileDetector.isReaderFile("novel.txt")).thenReturn(true);
        when(importService.importFile(OWNER_ID, FILE_ID)).thenReturn(item);

        Optional<UUID> result = autoImportService.importUploadedFile(uploaded("novel.txt", "text/plain"));

        assertThat(result).contains(ITEM_ID);
        verify(importService).importFile(OWNER_ID, FILE_ID);
    }

    @Test
    void propagatesImportFailureForTaskRetry() {
        when(fileDetector.isReaderFile("corrupt.epub")).thenReturn(true);
        when(importService.importFile(OWNER_ID, FILE_ID))
                .thenThrow(new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "导入失败"));

        assertThatThrownBy(() -> autoImportService.importUploadedFile(
                uploaded("corrupt.epub", "application/epub+zip")
        )).isInstanceOf(BusinessException.class);
    }

    private FileUploadedEvent uploaded(String fileName, String mimeType) {
        return new FileUploadedEvent(
                FILE_ID,
                UUID.fromString("50000000-0000-0000-0000-000000000001"),
                OWNER_ID,
                "omninest",
                "files/" + fileName,
                fileName,
                mimeType,
                1024,
                Instant.parse("2026-06-12T00:00:00Z")
        );
    }
}
