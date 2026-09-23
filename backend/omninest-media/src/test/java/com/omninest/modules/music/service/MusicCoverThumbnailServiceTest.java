package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileQueryService;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

class MusicCoverThumbnailServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID COVER_ID = UUID.fromString("71000000-0000-0000-0000-000000000001");
    private static final UUID THUMBNAIL_ID = UUID.fromString("71000000-0000-0000-0000-000000000002");
    private static final long MAX_SOURCE_BYTES = 8L * 1024 * 1024;
    private static final String FILE_NAME = "cover_300.jpg";

    private final DerivedAssetStorageService storageService = mock(DerivedAssetStorageService.class);
    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final MusicCoverThumbnailService service =
            new MusicCoverThumbnailService(storageService, fileQueryService);

    @Test
    void reusesStoredThumbnailWithoutDecodingSource() {
        when(storageService.findStoredFileNodeId(OWNER_ID, "MUSIC_COVER", COVER_ID, "THUMBNAIL", FILE_NAME))
                .thenReturn(Optional.of(THUMBNAIL_ID));

        Optional<UUID> result = service.ensureThumbnail(OWNER_ID, COVER_ID, 1024);

        assertThat(result).contains(THUMBNAIL_ID);
        verify(fileQueryService, never()).openReadableFileContent(any(), any());
    }

    @Test
    void skipsDerivationForSourcesAboveAcceptedSize() {
        when(storageService.findStoredFileNodeId(any(), any(), any(), any(), any())).thenReturn(Optional.empty());

        Optional<UUID> result = service.ensureThumbnail(OWNER_ID, COVER_ID, MAX_SOURCE_BYTES + 1);

        assertThat(result).isEmpty();
        verify(fileQueryService, never()).openReadableFileContent(any(), any());
    }

    @Test
    void derivesThumbnailAndStoresItUnderCoverKey() throws Exception {
        AtomicReference<Integer> storedWidth = new AtomicReference<>();
        when(storageService.findStoredFileNodeId(any(), any(), any(), any(), any())).thenReturn(Optional.empty());
        when(storageService.store(any(), any(), any(), any(), any(), any(), any(Path.class)))
                .thenAnswer(invocation -> {
                    storedWidth.set(readWidth(invocation.<Path>getArgument(6)));
                    return THUMBNAIL_ID;
                });
        stubSource(jpeg(900, 600));

        Optional<UUID> result = service.ensureThumbnail(OWNER_ID, COVER_ID, 4096);

        assertThat(result).contains(THUMBNAIL_ID);
        ArgumentCaptor<String> resourceType = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<UUID> resourceId = ArgumentCaptor.forClass(UUID.class);
        ArgumentCaptor<String> assetType = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<String> fileName = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<String> mimeType = ArgumentCaptor.forClass(String.class);
        verify(storageService).store(eq(OWNER_ID), resourceType.capture(), resourceId.capture(),
                assetType.capture(), fileName.capture(), mimeType.capture(), any(Path.class));
        assertThat(resourceType.getValue()).isEqualTo("MUSIC_COVER");
        assertThat(resourceId.getValue()).isEqualTo(COVER_ID);
        assertThat(assetType.getValue()).isEqualTo("THUMBNAIL");
        assertThat(fileName.getValue()).isEqualTo(FILE_NAME);
        assertThat(mimeType.getValue()).isEqualTo("image/jpeg");
        assertThat(storedWidth.get()).isEqualTo(300);
    }

    @Test
    void fallsBackWhenSourceIsNotADecodableImage() {
        when(storageService.findStoredFileNodeId(any(), any(), any(), any(), any())).thenReturn(Optional.empty());
        stubSource("not-an-image".getBytes(StandardCharsets.US_ASCII));

        Optional<UUID> result = service.ensureThumbnail(OWNER_ID, COVER_ID, 1024);

        assertThat(result).isEmpty();
        verify(storageService, never()).store(any(), any(), any(), any(), any(), any(), any(Path.class));
    }

    @Test
    void derivesOnceForConcurrentRequestsOfTheSameCover() throws Exception {
        AtomicInteger storeCalls = new AtomicInteger();
        CountDownLatch firstStoreEntered = new CountDownLatch(1);
        CountDownLatch releaseStores = new CountDownLatch(1);
        CountDownLatch secondCallStarted = new CountDownLatch(1);
        AtomicReference<Thread> secondThread = new AtomicReference<>();
        when(storageService.findStoredFileNodeId(any(), any(), any(), any(), any())).thenReturn(Optional.empty());
        when(storageService.store(any(), any(), any(), any(), any(), any(), any(Path.class)))
                .thenAnswer(invocation -> {
                    storeCalls.incrementAndGet();
                    firstStoreEntered.countDown();
                    releaseStores.await(10, TimeUnit.SECONDS);
                    return THUMBNAIL_ID;
                });
        stubSource(jpeg(800, 800));
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            Future<Optional<UUID>> first = executor.submit(() -> service.ensureThumbnail(OWNER_ID, COVER_ID, 4096));
            assertThat(firstStoreEntered.await(10, TimeUnit.SECONDS)).isTrue();
            Future<Optional<UUID>> second = executor.submit(() -> {
                secondThread.set(Thread.currentThread());
                secondCallStarted.countDown();
                return service.ensureThumbnail(OWNER_ID, COVER_ID, 4096);
            });
            assertThat(secondCallStarted.await(10, TimeUnit.SECONDS)).isTrue();
            awaitWaitingOnInFlight(secondThread.get());
            releaseStores.countDown();

            assertThat(first.get(10, TimeUnit.SECONDS)).contains(THUMBNAIL_ID);
            assertThat(second.get(10, TimeUnit.SECONDS)).contains(THUMBNAIL_ID);
            assertThat(storeCalls.get()).isEqualTo(1);
        } finally {
            executor.shutdownNow();
        }
    }

    @Test
    void fallsBackWhenDerivationConcurrencyIsSaturated() throws Exception {
        // 与 MusicCoverThumbnailService.MAX_CONCURRENT_DERIVATIONS 一致。
        CountDownLatch parked = new CountDownLatch(4);
        CountDownLatch release = new CountDownLatch(1);
        Set<UUID> openedCovers = ConcurrentHashMap.newKeySet();
        when(storageService.findStoredFileNodeId(any(), any(), any(), any(), any())).thenReturn(Optional.empty());
        when(fileQueryService.openReadableFileContent(eq(OWNER_ID), any())).thenAnswer(invocation -> {
            openedCovers.add(invocation.getArgument(1));
            parked.countDown();
            release.await(10, TimeUnit.SECONDS);
            return new FileContentStream(
                    new ByteArrayInputStream(new byte[]{0}),
                    FILE_NAME,
                    1,
                    "image/jpeg"
            );
        });
        ExecutorService executor = Executors.newFixedThreadPool(5);
        try {
            List<Future<Optional<UUID>>> busy = new ArrayList<>();
            for (int index = 0; index < 4; index++) {
                UUID coverId = UUID.randomUUID();
                busy.add(executor.submit(() -> service.ensureThumbnail(OWNER_ID, coverId, 4096)));
            }
            assertThat(parked.await(10, TimeUnit.SECONDS)).isTrue();
            Future<Optional<UUID>> extra = executor.submit(
                    () -> service.ensureThumbnail(OWNER_ID, UUID.randomUUID(), 4096));

            assertThat(extra.get(10, TimeUnit.SECONDS)).isEmpty();
            assertThat(openedCovers).hasSize(4);
            release.countDown();
            for (Future<Optional<UUID>> task : busy) {
                task.get(10, TimeUnit.SECONDS);
            }
        } finally {
            executor.shutdownNow();
        }
    }

    /**
     * 等第二个调用停在派生结果的等待上，确保它不会再自行生成一份。
     */
    private void awaitWaitingOnInFlight(Thread thread) throws InterruptedException {
        for (int attempt = 0; attempt < 200 && thread.getState() != Thread.State.TIMED_WAITING; attempt++) {
            Thread.sleep(10);
        }
        assertThat(thread.getState()).isEqualTo(Thread.State.TIMED_WAITING);
    }

    private void stubSource(byte[] payload) {
        when(fileQueryService.openReadableFileContent(OWNER_ID, COVER_ID)).thenAnswer(invocation ->
                new FileContentStream(
                        new ByteArrayInputStream(payload),
                        FILE_NAME,
                        payload.length,
                        "image/jpeg"
                ));
    }

    private int readWidth(Path output) {
        try (ImageInputStream input = ImageIO.createImageInputStream(output.toFile())) {
            Iterator<ImageReader> readers = ImageIO.getImageReaders(input);
            ImageReader reader = readers.next();
            try {
                reader.setInput(input, true, true);
                return reader.getWidth(0);
            } finally {
                reader.dispose();
            }
        } catch (IOException ex) {
            throw new UncheckedIOException(ex);
        }
    }

    private byte[] jpeg(int width, int height) {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = image.createGraphics();
        graphics.setColor(new Color(30, 60, 90));
        graphics.fillRect(0, 0, width, height);
        graphics.dispose();
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        try {
            ImageIO.write(image, "jpg", output);
        } catch (IOException ex) {
            throw new UncheckedIOException(ex);
        }
        return output.toByteArray();
    }
}
