package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.StorageImportTask;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * 外部导入重试续跑判定测试。
 *
 * @author OmniNest
 */
class ExternalImportResumeDetectorTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID PARENT_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID OBJECT_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    private final FileNodeRepository nodeRepository = mock(FileNodeRepository.class);
    private final FileObjectRepository objectRepository = mock(FileObjectRepository.class);

    @Test
    void detectsAlreadyImportedFileBySameNameAndContent(@TempDir Path tempDir) throws IOException {
        Path source = write(tempDir, "movie.mkv", "same-bytes");
        FileNode existing = node(OBJECT_ID);
        when(nodeRepository.findFirstByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, PARENT_ID, "movie.mkv"))
                .thenReturn(Optional.of(existing));
        when(objectRepository.findById(OBJECT_ID)).thenReturn(Optional.of(object(SAME_SHA)));

        Optional<FileNode> result = ExternalImportResumeDetector.findAlreadyImported(
                nodeRepository,
                objectRepository,
                task(),
                SpaceType.PERSONAL,
                PARENT_ID,
                "movie.mkv",
                source
        );

        assertThat(result).contains(existing);
    }

    @Test
    void keepsRenamePathWhenContentDiffers(@TempDir Path tempDir) throws IOException {
        Path source = write(tempDir, "movie.mkv", "new-bytes");
        when(nodeRepository.findFirstByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, PARENT_ID, "movie.mkv"))
                .thenReturn(Optional.of(node(OBJECT_ID)));
        when(objectRepository.findById(OBJECT_ID)).thenReturn(Optional.of(object(OLD_SHA)));

        Optional<FileNode> result = ExternalImportResumeDetector.findAlreadyImported(
                nodeRepository,
                objectRepository,
                task(),
                SpaceType.PERSONAL,
                PARENT_ID,
                "movie.mkv",
                source
        );

        assertThat(result).isEmpty();
    }

    @Test
    void skipsHashingWhenNameIsFree(@TempDir Path tempDir) throws IOException {
        Path source = write(tempDir, "movie.mkv", "same-bytes");
        when(nodeRepository.findFirstByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, PARENT_ID, "movie.mkv"))
                .thenReturn(Optional.empty());

        Optional<FileNode> result = ExternalImportResumeDetector.findAlreadyImported(
                nodeRepository,
                objectRepository,
                task(),
                SpaceType.PERSONAL,
                PARENT_ID,
                "movie.mkv",
                source
        );

        assertThat(result).isEmpty();
        // 常态导入不能因为续跑判定多查一次对象表。
        verify(objectRepository, never()).findById(any());
    }

    @Test
    void reusesImportRootOnlyWhileFolderStillExists() {
        StorageImportTask task = task();
        UUID rootId = UUID.fromString("40000000-0000-0000-0000-000000000001");
        task.setImportRootNodeId(rootId);
        FileNode folder = new FileNode();
        folder.setId(rootId);
        folder.setNodeType(NodeType.FOLDER.getValue());
        when(nodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(rootId, OWNER_ID))
                .thenReturn(Optional.of(folder));

        assertThat(ExternalImportResumeDetector.reusableRoot(
                nodeRepository, task, SpaceType.PERSONAL)).contains(rootId);

        when(nodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(rootId, OWNER_ID))
                .thenReturn(Optional.empty());
        assertThat(ExternalImportResumeDetector.reusableRoot(
                nodeRepository, task, SpaceType.PERSONAL)).isEmpty();
    }

    private Path write(Path dir, String name, String content) throws IOException {
        return Files.writeString(dir.resolve(name), content, StandardCharsets.UTF_8);
    }

    private static final String SAME_SHA = "7ad5509fac1a1be4a59ae87959468840d2808bab1b3cd5676733194aa82ef338";
    private static final String OLD_SHA = "8ee279698443302d84d6d6c0c747483b599cc3093d03a417940090d506762c2f";

    private StorageImportTask task() {
        StorageImportTask task = new StorageImportTask();
        task.setId(UUID.fromString("50000000-0000-0000-0000-000000000001"));
        task.setOwnerUserId(OWNER_ID);
        return task;
    }

    private FileNode node(UUID objectId) {
        FileNode node = new FileNode();
        node.setId(UUID.fromString("60000000-0000-0000-0000-000000000001"));
        node.setCurrentObjectId(objectId);
        return node;
    }

    private FileObject object(String sha256) {
        FileObject object = new FileObject();
        object.setId(OBJECT_ID);
        object.setSha256(sha256);
        return object;
    }
}
