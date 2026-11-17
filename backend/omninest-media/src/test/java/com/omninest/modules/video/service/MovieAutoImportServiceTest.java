package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.video.domain.MediaVideoItem;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class MovieAutoImportServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID FILE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private final MediaRuntimeConfigService configService = mock(MediaRuntimeConfigService.class);
    private final MovieScrapeService scrapeService = mock(MovieScrapeService.class);
    private final SimpleFileNameParser fileNameParser = new SimpleFileNameParser();
    private final MovieAutoImportService autoImportService =
            new MovieAutoImportService(configService, scrapeService, fileNameParser);

    @Test
    void skipsUploadedFileWhenAutoImportDisabled() {
        when(configService.autoImportEnabled()).thenReturn(false);

        Optional<UUID> result = autoImportService.importUploadedFile(uploaded("Inception.2010.mkv", "video/x-matroska"));

        assertThat(result).isEmpty();
        verify(scrapeService, never()).createScrapeTask(OWNER_ID, FILE_ID, false);
    }

    @Test
    void registersPendingVideoWithoutCreatingScrapeTaskWhenAutoImportEnabled() {
        UUID videoItemId = UUID.fromString("40000000-0000-0000-0000-000000000001");
        MediaVideoItem item = new MediaVideoItem();
        item.setId(videoItemId);
        when(configService.autoImportEnabled()).thenReturn(true);
        when(scrapeService.registerPendingVideo(OWNER_ID, FILE_ID)).thenReturn(item);

        Optional<UUID> result = autoImportService.importUploadedFile(uploaded("Inception.2010.mkv", "video/x-matroska"));

        assertThat(result).contains(videoItemId);
        verify(scrapeService).registerPendingVideo(OWNER_ID, FILE_ID);
        verify(scrapeService, never()).createScrapeTask(OWNER_ID, FILE_ID, false);
    }

    @Test
    void skipsNonVideoFileWhenAutoImportEnabled() {
        when(configService.autoImportEnabled()).thenReturn(true);

        Optional<UUID> result = autoImportService.importUploadedFile(uploaded("readme.txt", "text/plain"));

        assertThat(result).isEmpty();
        verify(scrapeService, never()).createScrapeTask(OWNER_ID, FILE_ID, false);
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
                Instant.parse("2026-05-21T00:00:00Z")
        );
    }
}
