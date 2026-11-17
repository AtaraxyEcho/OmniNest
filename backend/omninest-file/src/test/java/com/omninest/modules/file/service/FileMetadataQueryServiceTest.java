package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 文件元数据查询服务测试。
 *
 * @author OmniNest
 */
class FileMetadataQueryServiceTest {

    private static final UUID FILE_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OBJECT_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final FileNodeRepository fileNodeRepository = mock(FileNodeRepository.class);
    private final com.omninest.modules.file.repository.FileNodeScanQueryRepository scanQueryRepository =
            mock(com.omninest.modules.file.repository.FileNodeScanQueryRepository.class);
    private final FileObjectRepository fileObjectRepository = mock(FileObjectRepository.class);
    private final FileMetadataQueryService service = new FileMetadataQueryService(
            fileNodeRepository, scanQueryRepository, fileObjectRepository);

    /**
     * 验证文件实体被映射为不可变描述符。
     */
    @Test
    void findByIdMapsDescriptor() {
        FileNode node = new FileNode();
        node.setId(FILE_ID);
        node.setName("song.flac");
        node.setNodeType("FILE");
        node.setSpaceType(SpaceType.SHARED);
        node.setCurrentObjectId(OBJECT_ID);
        when(fileNodeRepository.findById(FILE_ID)).thenReturn(Optional.of(node));

        var result = service.findById(FILE_ID).orElseThrow();

        assertThat(result.name()).isEqualTo("song.flac");
        assertThat(result.spaceType()).isEqualTo(SpaceType.SHARED);
        assertThat(result.currentObjectId()).isEqualTo(OBJECT_ID);
    }

    /**
     * 验证文件对象实体被映射为不可变描述符。
     */
    @Test
    void findObjectByIdMapsDescriptor() {
        FileObject object = new FileObject();
        object.setId(OBJECT_ID);
        object.setBucketName("files");
        object.setObjectKey("owner/song.flac");
        object.setSizeBytes(4096);
        when(fileObjectRepository.findById(OBJECT_ID)).thenReturn(Optional.of(object));

        var result = service.findObjectById(OBJECT_ID).orElseThrow();

        assertThat(result.bucketName()).isEqualTo("files");
        assertThat(result.objectKey()).isEqualTo("owner/song.flac");
        assertThat(result.sizeBytes()).isEqualTo(4096);
    }

    /**
     * 验证同目录文件查询返回不可变描述符。
     */
    @Test
    void listOwnedActiveChildrenMapsDescriptors() {
        UUID ownerId = UUID.fromString("30000000-0000-0000-0000-000000000001");
        UUID parentId = UUID.fromString("40000000-0000-0000-0000-000000000001");
        FileNode node = new FileNode();
        node.setId(FILE_ID);
        node.setName("song.lrc");
        when(fileNodeRepository.findByOwnerUserIdAndParentIdAndDeletedFalse(ownerId, parentId))
                .thenReturn(List.of(node));

        var result = service.listOwnedActiveChildren(ownerId, parentId);

        assertThat(result).extracting(descriptor -> descriptor.name()).containsExactly("song.lrc");
    }

    /**
     * 验证共享文件候选查询返回不可变描述符。
     */
    @Test
    void listSharedVisibleToUserMapsDescriptors() {
        UUID userId = UUID.fromString("50000000-0000-0000-0000-000000000001");
        FileNode node = new FileNode();
        node.setId(FILE_ID);
        node.setName("shared.flac");
        when(fileNodeRepository.findSharedFilesVisibleToUser(userId)).thenReturn(List.of(node));

        var result = service.listSharedVisibleToUser(userId);

        assertThat(result).extracting(descriptor -> descriptor.name()).containsExactly("shared.flac");
    }

    /**
     * 验证批量内容摘要以文件节点 ID 返回且过滤空摘要。
     */
    @Test
    void findContentSha256ByFileNodeIdsMapsNodeIdsWithoutExposingObjectLocation() {
        UUID secondFileId = UUID.fromString("10000000-0000-0000-0000-000000000002");
        UUID secondObjectId = UUID.fromString("20000000-0000-0000-0000-000000000002");
        FileNode firstNode = new FileNode();
        firstNode.setId(FILE_ID);
        firstNode.setCurrentObjectId(OBJECT_ID);
        FileNode secondNode = new FileNode();
        secondNode.setId(secondFileId);
        secondNode.setCurrentObjectId(secondObjectId);
        FileObject firstObject = new FileObject();
        firstObject.setId(OBJECT_ID);
        firstObject.setSha256("abc123");
        FileObject secondObject = new FileObject();
        secondObject.setId(secondObjectId);
        secondObject.setSha256(null);
        when(fileNodeRepository.findAllById(List.of(FILE_ID, secondFileId)))
                .thenReturn(List.of(firstNode, secondNode));
        when(fileObjectRepository.findAllById(List.of(OBJECT_ID, secondObjectId)))
                .thenReturn(List.of(firstObject, secondObject));

        var result = service.findContentSha256ByFileNodeIds(List.of(FILE_ID, secondFileId));

        assertThat(result).containsExactlyEntriesOf(Map.of(FILE_ID, "abc123"));
    }
}
