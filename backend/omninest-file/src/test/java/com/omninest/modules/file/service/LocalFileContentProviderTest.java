package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileContentRef;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.StorageLocation;
import com.omninest.modules.file.repository.FileContentRefRepository;
import com.omninest.modules.file.repository.StorageLocationRepository;
import java.nio.file.Path;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * 本地文件内容提供者测试。
 */
class LocalFileContentProviderTest {

    private static final UUID FILE_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID LOCATION_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final FileContentRefRepository contentRefRepository =
            mock(FileContentRefRepository.class);
    private final StorageLocationRepository storageLocationRepository =
            mock(StorageLocationRepository.class);
    private final LocalMediaPathResolver pathResolver = mock(LocalMediaPathResolver.class);
    private final LocalContentAccessTokenService tokenService =
            mock(LocalContentAccessTokenService.class);
    private final LocalMediaRuntimeConfigService runtimeConfigService =
            mock(LocalMediaRuntimeConfigService.class);

    private LocalFileContentProvider provider;

    @BeforeEach
    void setUp() {
        provider = new LocalFileContentProvider(
                contentRefRepository,
                storageLocationRepository,
                pathResolver,
                tokenService,
                runtimeConfigService
        );
        when(runtimeConfigService.isEnabled()).thenReturn(true);
    }

    @Test
    void findRangeResource_doesNotWriteAvailabilityOnRead(
            @org.junit.jupiter.api.io.TempDir Path tempDir
    ) throws Exception {
        Path file = tempDir.resolve("movie.mkv");
        java.nio.file.Files.write(file, new byte[] {1, 2, 3, 4});
        FileNode node = new FileNode();
        node.setId(FILE_ID);
        node.setName("movie.mkv");
        node.setMimeType("video/x-matroska");

        FileContentRef reference = reference("MISSING");
        StorageLocation location = location(true);

        when(contentRefRepository.findByFileNodeId(FILE_ID)).thenReturn(Optional.of(reference));
        when(storageLocationRepository.findById(LOCATION_ID)).thenReturn(Optional.of(location));
        when(pathResolver.resolveFile(location, "movies/movie.mkv")).thenReturn(file);

        var resource = provider.findRangeResource(node);

        assertThat(resource).isPresent();
        // C3：读路径不写库，可用性由扫描/维护流程更新。
        assertThat(reference.getAvailabilityStatus()).isEqualTo("MISSING");
        verify(contentRefRepository, never()).save(any(FileContentRef.class));
    }

    @Test
    void findRangeResource_throwsWhenLocationDisabled() {
        FileNode node = new FileNode();
        node.setId(FILE_ID);
        FileContentRef reference = reference("AVAILABLE");
        StorageLocation location = location(false);

        when(contentRefRepository.findByFileNodeId(FILE_ID)).thenReturn(Optional.of(reference));
        when(storageLocationRepository.findById(LOCATION_ID)).thenReturn(Optional.of(location));

        assertThatThrownBy(() -> provider.findRangeResource(node))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.DEPENDENCY_UNAVAILABLE);
        verify(contentRefRepository, never()).save(any());
    }

    private FileContentRef reference(String status) {
        FileContentRef reference = new FileContentRef();
        reference.setId(UUID.randomUUID());
        reference.setOwnerUserId(UUID.randomUUID());
        reference.setFileNodeId(FILE_ID);
        reference.setStorageLocationId(LOCATION_ID);
        reference.setRelativePath("movies/movie.mkv");
        reference.setAvailabilityStatus(status);
        reference.setMissingConfirmations(2);
        reference.setMissingSince(Instant.now());
        reference.setLastSeenAt(Instant.now());
        return reference;
    }

    private StorageLocation location(boolean enabled) {
        StorageLocation location = new StorageLocation();
        location.setId(LOCATION_ID);
        location.setName("媒体库");
        location.setProviderType("LOCAL_FILESYSTEM");
        location.setMountKey("media");
        location.setRelativeRoot(".");
        location.setEnabled(enabled);
        return location;
    }
}
