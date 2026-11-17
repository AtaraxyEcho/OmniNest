package com.omninest.modules.file.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.config.LocalMediaStorageProperties;
import com.omninest.modules.file.domain.StorageLocation;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * 本地媒体路径解析安全测试。
 *
 * @author OmniNest
 */
class LocalMediaPathResolverTest {

    @TempDir
    Path tempDirectory;

    private LocalMediaPathResolver resolver;
    private StorageLocation location;

    @BeforeEach
    void setUp() throws IOException {
        Files.createDirectories(tempDirectory.resolve("library/Movies"));
        Files.writeString(tempDirectory.resolve("library/Movies/demo.mkv"), "video");

        LocalMediaStorageProperties properties = new LocalMediaStorageProperties();
        properties.setEnabled(true);
        properties.setMounts(Map.of(
                "media",
                new LocalMediaStorageProperties.MountProperties(
                        tempDirectory.toString(),
                        "/mnt/local-media"
                )
        ));
        resolver = new LocalMediaPathResolver(properties);

        location = new StorageLocation();
        location.setId(UUID.randomUUID());
        location.setEnabled(true);
        location.setMountKey("media");
        location.setRelativeRoot("library");
    }

    @Test
    void shouldResolveFileInsideConfiguredRoot() {
        Path resolved = resolver.resolveFile(location, "Movies/demo.mkv");

        assertEquals(tempDirectory.resolve("library/Movies/demo.mkv").toAbsolutePath(), resolved);
    }

    @Test
    void shouldRejectParentTraversal() {
        assertThrows(
                BusinessException.class,
                () -> resolver.resolveFile(location, "../outside.mkv")
        );
    }

    @Test
    void shouldRejectAbsolutePath() {
        assertThrows(
                BusinessException.class,
                () -> resolver.resolveFile(location, tempDirectory.resolve("outside.mkv").toString())
        );
    }

    @Test
    void shouldRejectWindowsDriveRelativePath() {
        assertThrows(
                BusinessException.class,
                () -> resolver.resolveFile(location, "C:Movies/demo.mkv")
        );
    }

    @Test
    void shouldRejectControlCharacters() {
        assertThrows(
                BusinessException.class,
                () -> resolver.resolveFile(location, "Movies/demo\u0001.mkv")
        );
    }

    @Test
    void shouldCreateReadOnlyContainerInputPath() {
        String processPath = resolver.resolveProcessPath(location, "Movies/demo.mkv");

        assertEquals("/mnt/local-media/library/Movies/demo.mkv", processPath);
    }
}
