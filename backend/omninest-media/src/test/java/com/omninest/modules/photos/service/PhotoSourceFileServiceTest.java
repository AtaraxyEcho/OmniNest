package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.photos.config.PhotoMediaLimitsProperties;
import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;

/**
 * 照片源文件受限暂存和生命周期测试。
 *
 * @author OmniNest
 */
class PhotoSourceFileServiceTest {

    private final FileQueryService fileQueryService = mock(FileQueryService.class);
    private final PhotoFileDetector fileDetector = new PhotoFileDetector();
    private final PhotoMediaLimitsProperties properties = new PhotoMediaLimitsProperties();
    private final PhotoInputGuard inputGuard = new PhotoInputGuard(properties);
    private final PhotoSourceFileService service = new PhotoSourceFileService(
            fileQueryService,
            fileDetector,
            inputGuard
    );

    @Test
    void stageOwnedDeletesTemporaryFileWhenHandleCloses() throws Exception {
        UUID ownerUserId = UUID.randomUUID();
        UUID fileNodeId = UUID.randomUUID();
        byte[] content = new byte[]{1, 2, 3, 4};
        when(fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId))
                .thenReturn(new FileContentStream(
                        new ByteArrayInputStream(content),
                        "photo.jpg",
                        content.length,
                        "image/jpeg"
                ));
        AtomicReference<Path> stagedPath = new AtomicReference<>();

        try (PhotoSourceFileService.StagedPhotoFile staged = service.stageOwned(ownerUserId, fileNodeId)) {
            stagedPath.set(staged.path());
            assertThat(Files.readAllBytes(staged.path())).containsExactly(content);
            assertThat(staged.fileName()).isEqualTo("photo.jpg");
        }

        assertThat(stagedPath.get()).doesNotExist();
    }

    @Test
    void stageInputRejectsStreamThatExceedsConfiguredLimit() {
        properties.setMaxStandardFileBytes(3);

        assertThatThrownBy(() -> service.stageInput(
                new ByteArrayInputStream(new byte[]{1, 2, 3, 4}),
                "photo.jpg",
                "image/jpeg"
        ))
                .isInstanceOf(BusinessException.class)
                .hasMessage("照片源文件超过大小限制");
    }

    @Test
    void stageInputKeepsConcurrentLargeStreamsBoundedAndCleansFiles() throws Exception {
        int streamCount = 32;
        int bytesPerStream = 2 * 1024 * 1024;
        AtomicInteger maxRequestedBytes = new AtomicInteger();
        CountDownLatch startGate = new CountDownLatch(1);
        List<PhotoSourceFileService.StagedPhotoFile> stagedFiles = new ArrayList<>();

        try (ExecutorService executor = Executors.newFixedThreadPool(16)) {
            List<Future<PhotoSourceFileService.StagedPhotoFile>> futures = IntStream.range(0, streamCount)
                    .mapToObj(index -> executor.submit(() -> {
                        startGate.await();
                        try (InputStream input = new GeneratedInputStream(bytesPerStream, maxRequestedBytes)) {
                            return service.stageInput(
                                    input,
                                    "photo-" + index + ".jpg",
                                    "image/jpeg"
                            );
                        }
                    }))
                    .toList();
            startGate.countDown();
            for (Future<PhotoSourceFileService.StagedPhotoFile> future : futures) {
                stagedFiles.add(future.get());
            }
        }

        List<Path> stagedPaths = stagedFiles.stream()
                .map(PhotoSourceFileService.StagedPhotoFile::path)
                .toList();
        try {
            assertThat(stagedFiles).hasSize(streamCount)
                    .allSatisfy(staged -> {
                        assertThat(staged.sizeBytes()).isEqualTo(bytesPerStream);
                        assertThat(staged.path()).exists();
                    });
            assertThat(maxRequestedBytes).hasValue(8192);
        } finally {
            stagedFiles.forEach(PhotoSourceFileService.StagedPhotoFile::close);
        }
        assertThat(stagedPaths).allSatisfy(path -> assertThat(path).doesNotExist());
    }

    /**
     * 生成不持有完整负载的输入流，并记录调用方单次请求的最大字节数。
     *
     * @author OmniNest
     */
    private static final class GeneratedInputStream extends InputStream {

        private final AtomicInteger maxRequestedBytes;
        private int remainingBytes;

        private GeneratedInputStream(int totalBytes, AtomicInteger maxRequestedBytes) {
            this.remainingBytes = totalBytes;
            this.maxRequestedBytes = maxRequestedBytes;
        }

        @Override
        public int read() {
            if (remainingBytes == 0) {
                return -1;
            }
            remainingBytes--;
            return 0;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) {
            if (remainingBytes == 0) {
                return -1;
            }
            maxRequestedBytes.accumulateAndGet(length, Math::max);
            int bytesRead = Math.min(remainingBytes, length);
            remainingBytes -= bytesRead;
            return bytesRead;
        }
    }
}
