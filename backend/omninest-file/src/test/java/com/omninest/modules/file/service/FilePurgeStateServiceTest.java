package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileVersion;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.event.FilePurgeRequestedEvent;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 彻底删除的配额释放口径测试。
 *
 * @author OmniNest
 */
class FilePurgeStateServiceTest {

    private static final UUID OBJECT_A = UUID.fromString("00000000-0000-0000-0000-00000000000a");
    private static final UUID OBJECT_B = UUID.fromString("00000000-0000-0000-0000-00000000000b");
    private static final UUID OBJECT_C = UUID.fromString("00000000-0000-0000-0000-00000000000c");

    @Test
    @DisplayName("无历史版本时按节点自身大小释放")
    void releasesNodeBytesWithoutVersions() {
        UUID nodeId = UUID.randomUUID();

        long released = FilePurgeStateService.quotaReleaseBytes(
                List.of(fileNode(nodeId, OBJECT_A, 1000L)),
                List.of(),
                Map.of(OBJECT_A, 1000L));

        assertThat(released).isEqualTo(1000L);
    }

    @Test
    @DisplayName("共享空间节点不释放个人配额")
    void doesNotReleaseSharedOrNonPersonalNodes() {
        UUID shared = UUID.randomUUID();
        UUID personal = UUID.randomUUID();
        FileNode sharedNode = fileNode(shared, OBJECT_A, 1000L);
        sharedNode.setSpaceType(SpaceType.SHARED);

        long released = FilePurgeStateService.quotaReleaseBytes(
                List.of(sharedNode, fileNode(personal, OBJECT_B, 300L)),
                List.of(version(shared, OBJECT_A, 1), version(personal, OBJECT_C, 2)),
                Map.of(OBJECT_A, 1000L, OBJECT_B, 300L, OBJECT_C, 200L));

        // 共享文件在软删除时已退还共享用量，个人账本从未计入，不能二次扣减
        assertThat(released).isEqualTo(500L);
    }

    @Test
    @DisplayName("系统派生与只读本地库节点写入时未加计，彻底删除不得扣减个人配额")
    void doesNotReleaseUnchargedDerivedAndLocalFilesystemNodes() {
        UUID uploadId = UUID.randomUUID();
        UUID thumbnailId = UUID.randomUUID();
        UUID localMovieId = UUID.randomUUID();
        FileNode thumbnail = fileNode(thumbnailId, OBJECT_B, 30_000L);
        thumbnail.setSourceType("DERIVED");
        thumbnail.setNormalizedPath("/.metadata/PHOTO_ITEM/" + thumbnailId + "/THUMBNAIL/thumb.jpg");
        FileNode localMovie = fileNode(localMovieId, OBJECT_C, 5_000_000L);
        localMovie.setSourceType("LOCAL_FILESYSTEM");
        localMovie.setNormalizedPath("/.metadata/LOCAL_MEDIA/" + localMovieId + "/SOURCE.mkv");

        long released = FilePurgeStateService.quotaReleaseBytes(
                List.of(fileNode(uploadId, OBJECT_A, 1000L), thumbnail, localMovie),
                List.of(),
                Map.of(OBJECT_A, 1000L, OBJECT_B, 30_000L, OBJECT_C, 5_000_000L));

        assertThat(released).isEqualTo(1000L);
    }

    @Test
    @DisplayName("背景图原片与编辑版本写入时已加计，彻底删除必须照常释放")
    void releasesChargedDerivedNodes() {
        UUID backdropId = UUID.randomUUID();
        UUID editVersionId = UUID.randomUUID();
        FileNode backdrop = fileNode(backdropId, OBJECT_A, 4_000_000L);
        backdrop.setSourceType("DERIVED");
        backdrop.setNormalizedPath("/.metadata/BACKDROP/" + backdropId + "/ORIGINAL/wallpaper.png");
        FileNode editVersion = fileNode(editVersionId, OBJECT_B, 800_000L);
        editVersion.setSourceType("DERIVED");
        editVersion.setNormalizedPath("/.metadata/PHOTO_ITEM/" + editVersionId + "/EDIT_VERSION/edited.jpg");

        long released = FilePurgeStateService.quotaReleaseBytes(
                List.of(backdrop, editVersion),
                List.of(),
                Map.of(OBJECT_A, 4_000_000L, OBJECT_B, 800_000L));

        assertThat(released).isEqualTo(4_800_000L);
    }

    @Test
    @DisplayName("历史版本对象一并释放，否则版本字节永久留在已用配额上")
    void releasesRetainedVersionObjects() {
        UUID nodeId = UUID.randomUUID();

        long released = FilePurgeStateService.quotaReleaseBytes(
                List.of(fileNode(nodeId, OBJECT_B, 1500L)),
                List.of(version(nodeId, OBJECT_A, 1)),
                Map.of(OBJECT_B, 1500L, OBJECT_A, 1000L));

        assertThat(released).isEqualTo(2500L);
    }

    @Test
    @DisplayName("恢复只是换位：与当前对象同引用的版本行与重复行都不另计")
    void doesNotDoubleCountRotatedOrDuplicatedVersionRows() {
        UUID nodeId = UUID.randomUUID();

        long released = FilePurgeStateService.quotaReleaseBytes(
                List.of(fileNode(nodeId, OBJECT_A, 1000L)),
                List.of(
                        version(nodeId, OBJECT_A, 1),
                        version(nodeId, OBJECT_B, 2),
                        version(nodeId, OBJECT_B, 3)),
                Map.of(OBJECT_A, 1000L, OBJECT_B, 700L));

        assertThat(released).isEqualTo(1700L);
    }

    @Test
    @DisplayName("两个节点各自持有同一对象的占用时分别释放")
    void releasesEachNodeShareOfACommonObject() {
        UUID source = UUID.randomUUID();
        UUID copy = UUID.randomUUID();

        long released = FilePurgeStateService.quotaReleaseBytes(
                List.of(fileNode(source, OBJECT_A, 1000L), fileNode(copy, OBJECT_C, 900L)),
                List.of(version(copy, OBJECT_A, 1)),
                Map.of(OBJECT_A, 1000L, OBJECT_C, 900L));

        assertThat(released).isEqualTo(2900L);
    }

    @Test
    @DisplayName("文件夹不贡献字节，对象行缺失时按零计不抛错")
    void skipsFoldersAndUnknownObjects() {
        UUID folderId = UUID.randomUUID();
        UUID nodeId = UUID.randomUUID();
        FileNode folder = new FileNode();
        folder.setId(folderId);
        folder.setNodeType(NodeType.FOLDER.getValue());
        folder.setSizeBytes(0L);

        long released = FilePurgeStateService.quotaReleaseBytes(
                List.of(folder, fileNode(nodeId, OBJECT_A, 10L)),
                List.of(version(nodeId, OBJECT_B, 1)),
                Map.of(OBJECT_A, 10L));

        assertThat(released).isEqualTo(10L);
    }

    @Test
    @DisplayName("共享空间粉碎任务允许目录内多成员上传的子文件")
    void allowsSharedSubtreeWithDifferentUploaders() {
        UUID taskId = UUID.randomUUID();
        UUID owner = UUID.randomUUID();
        FileNode shared = fileNode(UUID.randomUUID(), OBJECT_A, 10L);
        shared.setSpaceType(SpaceType.SHARED);
        shared.setOwnerUserId(UUID.randomUUID());

        FilePurgeStateService.validateTaskNodes(
                new FilePurgeRequestedEvent(taskId, owner, shared.getId()), List.of(shared));
    }

    @Test
    @DisplayName("个人空间粉碎任务仍拒绝混入他人的节点")
    void rejectsPersonalNodeOwnedByAnotherUser() {
        UUID taskId = UUID.randomUUID();
        UUID owner = UUID.randomUUID();
        FileNode personal = fileNode(UUID.randomUUID(), OBJECT_A, 10L);
        personal.setSpaceType(SpaceType.PERSONAL);
        personal.setOwnerUserId(UUID.randomUUID());

        assertThatThrownBy(() -> FilePurgeStateService.validateTaskNodes(
                        new FilePurgeRequestedEvent(taskId, owner, personal.getId()), List.of(personal)))
                .isInstanceOf(BusinessException.class)
                .extracting(ex -> ((BusinessException) ex).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    @DisplayName("失效事件按真实上传者分组，共享子文件的删除者不会吞掉上传者事件")
    void groupsNodeIdsByRealOwner() {
        UUID uploaderA = UUID.randomUUID();
        UUID uploaderB = UUID.randomUUID();
        FileNode first = fileNode(UUID.randomUUID(), OBJECT_A, 10L);
        first.setSpaceType(SpaceType.SHARED);
        first.setOwnerUserId(uploaderA);
        first.setUploadedBy(uploaderA);
        FileNode second = fileNode(UUID.randomUUID(), OBJECT_B, 20L);
        second.setSpaceType(SpaceType.SHARED);
        second.setOwnerUserId(uploaderB);
        second.setUploadedBy(uploaderB);

        Map<UUID, List<UUID>> grouped = FilePurgeStateService.groupNodeIdsByOwner(List.of(first, second));

        assertThat(grouped)
                .containsEntry(uploaderA, List.of(first.getId()))
                .containsEntry(uploaderB, List.of(second.getId()));
    }

    private static FileNode fileNode(UUID nodeId, UUID currentObjectId, long sizeBytes) {
        FileNode node = new FileNode();
        node.setId(nodeId);
        node.setNodeType(NodeType.FILE.getValue());
        node.setCurrentObjectId(currentObjectId);
        node.setSizeBytes(sizeBytes);
        return node;
    }

    private static FileVersion version(UUID nodeId, UUID objectId, int versionNo) {
        FileVersion version = new FileVersion();
        version.setFileNodeId(nodeId);
        version.setObjectId(objectId);
        version.setVersionNo(versionNo);
        return version;
    }
}
