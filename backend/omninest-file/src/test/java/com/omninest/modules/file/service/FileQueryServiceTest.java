package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.FilePermission;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.CreateFolderRequest;
import com.omninest.modules.file.dto.MoveFileNodeRequest;
import com.omninest.modules.file.dto.RenameFileNodeRequest;
import com.omninest.modules.file.event.FileNodesDeletedEvent;
import com.omninest.modules.file.event.FileNodesRestoredEvent;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.search.service.FileSearchIndexService;
import java.io.ByteArrayInputStream;
import java.net.URI;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.data.domain.SliceImpl;

/**
 * 文件查询、内容访问与生命周期服务测试。
 *
 * @author OmniNest
 */
class FileQueryServiceTest {
    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OTHER_OWNER_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");

    private final FileNodeRepository fileNodeRepository = Mockito.mock(FileNodeRepository.class);
    private final FileObjectRepository fileObjectRepository = Mockito.mock(FileObjectRepository.class);
    private final ObjectStorageClient objectStorageClient = Mockito.mock(ObjectStorageClient.class);
    private final ApplicationEventPublisher eventPublisher = Mockito.mock(ApplicationEventPublisher.class);
    private final FileSearchIndexService fileSearchIndexService =
            Mockito.mock(FileSearchIndexService.class);
    private final FilePermissionService filePermissionService =
            Mockito.mock(FilePermissionService.class);
    private final FileLifecycleGuard fileLifecycleGuard = Mockito.mock(FileLifecycleGuard.class);
    private final UserSyncEventRecorder syncEventRecorder = Mockito.mock(UserSyncEventRecorder.class);
    private final MinioFileContentProvider minioFileContentProvider = new MinioFileContentProvider(
            fileObjectRepository,
            objectStorageClient
    );
    private final FileContentAccessService fileContentAccessService = new FileContentAccessService(
            List.of(minioFileContentProvider),
            fileNodeRepository,
            fileObjectRepository,
            new LocalContentAccessTokenService()
    );
    private final FileQueryService fileQueryService = new FileQueryService(
            fileNodeRepository,
            fileContentAccessService,
            filePermissionService,
            fileLifecycleGuard,
            eventPublisher,
            fileSearchIndexService,
            syncEventRecorder
    );

    @Test
    void rootListOnlyReturnsCurrentUsersNodesAndSortsFoldersFirst() {
        FileNode file = node(OWNER_ID, null, "FILE", "b.txt", "/b.txt");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "A", "/A");
        FileNode localVideo = node(OWNER_ID, null, "FILE", "local.mkv", "/.local-media/local.mkv");
        localVideo.setSourceType(SourceType.LOCAL_FILESYSTEM.getValue());
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL))
                .thenReturn(List.of(file, folder, localVideo));

        var result = fileQueryService.listFiles(OWNER_ID, null);

        assertThat(result).extracting("name").containsExactly("A", "b.txt");
    }

    @Test
    void deleteNodeRejectsLocalReadOnlyMediaReference() {
        UUID fileId = UUID.randomUUID();
        FileNode localVideo = node(OWNER_ID, null, "FILE", "local.mkv", "/.local-media/local.mkv");
        localVideo.setId(fileId);
        localVideo.setSourceType(SourceType.LOCAL_FILESYSTEM.getValue());
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, OWNER_ID))
                .thenReturn(Optional.of(localVideo));

        assertThatThrownBy(() -> fileQueryService.deleteNode(OWNER_ID, fileId))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不能通过文件管理器修改");
        verify(fileNodeRepository, never()).save(localVideo);
    }

    @Test
    void listFilesFiltersByCommonFileCategory() {
        FileNode movie = node(OWNER_ID, null, "FILE", "movie.mp4", "/movie.mp4");
        movie.setMimeType("video/mp4");
        FileNode song = node(OWNER_ID, null, "FILE", "song.flac", "/song.flac");
        song.setMimeType("audio/flac");
        FileNode novel = node(OWNER_ID, null, "FILE", "story.epub", "/story.epub");
        novel.setMimeType("application/epub+zip");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Media", "/Media");
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndDeletedFalse(OWNER_ID, SpaceType.PERSONAL))
                .thenReturn(List.of(song, movie, folder, novel));

        var result = fileQueryService.listFiles(OWNER_ID, null, "video");

        assertThat(result).extracting("name").containsExactly("movie.mp4");
    }

    @Test
    void listFilesClassifiesComicAndNovelByExtension() {
        FileNode comic = node(OWNER_ID, null, "FILE", "chapter.cbz", "/chapter.cbz");
        comic.setMimeType("application/zip");
        FileNode novel = node(OWNER_ID, null, "FILE", "book.azw3", "/book.azw3");
        novel.setMimeType("application/octet-stream");
        FileNode archive = node(OWNER_ID, null, "FILE", "backup.zip", "/backup.zip");
        archive.setMimeType("application/zip");
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndDeletedFalse(OWNER_ID, SpaceType.PERSONAL))
                .thenReturn(List.of(archive, comic, novel));

        var comics = fileQueryService.listFiles(OWNER_ID, null, "comic");
        var novels = fileQueryService.listFiles(OWNER_ID, null, "novel");

        assertThat(comics).extracting("name").containsExactly("chapter.cbz");
        assertThat(novels).extracting("name").containsExactly("book.azw3");
    }

    @Test
    void listFilesClassifiesCommonMediaByExtensionWhenMimeTypeIsGeneric() {
        FileNode image = node(OWNER_ID, null, "FILE", "cover.jpg", "/cover.jpg");
        image.setMimeType("application/octet-stream");
        FileNode video = node(OWNER_ID, null, "FILE", "clip.mkv", "/clip.mkv");
        video.setMimeType("application/octet-stream");
        FileNode audio = node(OWNER_ID, null, "FILE", "song.mp3", "/song.mp3");
        audio.setMimeType("application/octet-stream");
        FileNode document = node(OWNER_ID, null, "FILE", "report.pdf", "/report.pdf");
        document.setMimeType("application/octet-stream");
        FileNode archive = node(OWNER_ID, null, "FILE", "backup.zip", "/backup.zip");
        archive.setMimeType("application/octet-stream");
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndDeletedFalse(OWNER_ID, SpaceType.PERSONAL))
                .thenReturn(List.of(image, video, audio, document, archive));

        var images = fileQueryService.listFiles(OWNER_ID, null, "image");
        var videos = fileQueryService.listFiles(OWNER_ID, null, "video");
        var audios = fileQueryService.listFiles(OWNER_ID, null, "audio");
        var documents = fileQueryService.listFiles(OWNER_ID, null, "document");
        var archives = fileQueryService.listFiles(OWNER_ID, null, "archive");

        assertThat(images).extracting("name").containsExactly("cover.jpg");
        assertThat(videos).extracting("name").containsExactly("clip.mkv");
        assertThat(audios).extracting("name").containsExactly("song.mp3");
        assertThat(documents).extracting("name").containsExactly("report.pdf");
        assertThat(archives).extracting("name").containsExactly("backup.zip");
    }

    @Test
    void listFilesFiltersCategoryAcrossNestedFilesFromAllFilesRoot() {
        UUID musicFolderId = UUID.fromString("30000000-0000-0000-0000-000000000002");
        UUID booksFolderId = UUID.fromString("30000000-0000-0000-0000-000000000003");
        FileNode musicFolder = node(OWNER_ID, null, "FOLDER", "Music", "/Music");
        musicFolder.setId(musicFolderId);
        FileNode booksFolder = node(OWNER_ID, null, "FOLDER", "Books", "/Books");
        booksFolder.setId(booksFolderId);
        FileNode song = node(OWNER_ID, musicFolderId, "FILE", "song.mp3", "/Music/song.mp3");
        song.setMimeType("application/octet-stream");
        FileNode cover = node(OWNER_ID, booksFolderId, "FILE", "cover.jpg", "/Books/cover.jpg");
        cover.setMimeType("application/octet-stream");
        FileNode clip = node(OWNER_ID, musicFolderId, "FILE", "clip.mkv", "/Music/clip.mkv");
        clip.setMimeType("application/octet-stream");
        FileNode report = node(OWNER_ID, booksFolderId, "FILE", "report.pdf", "/Books/report.pdf");
        report.setMimeType("application/octet-stream");
        FileNode comic = node(OWNER_ID, booksFolderId, "FILE", "chapter.cbz", "/Books/chapter.cbz");
        comic.setMimeType("application/zip");
        FileNode novel = node(OWNER_ID, booksFolderId, "FILE", "book.azw3", "/Books/book.azw3");
        novel.setMimeType("application/octet-stream");
        FileNode archive = node(OWNER_ID, booksFolderId, "FILE", "backup.zip", "/Books/backup.zip");
        archive.setMimeType("application/octet-stream");
        FileNode unknown = node(OWNER_ID, booksFolderId, "FILE", "raw.bin", "/Books/raw.bin");
        unknown.setMimeType("application/octet-stream");
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndDeletedFalse(OWNER_ID, SpaceType.PERSONAL))
                .thenReturn(List.of(
                        musicFolder,
                        booksFolder,
                        song,
                        cover,
                        clip,
                        report,
                        comic,
                        novel,
                        archive,
                        unknown
                ));

        var audios = fileQueryService.listFiles(OWNER_ID, null, "audio");
        var images = fileQueryService.listFiles(OWNER_ID, null, "image");
        var videos = fileQueryService.listFiles(OWNER_ID, null, "video");
        var documents = fileQueryService.listFiles(OWNER_ID, null, "document");
        var comics = fileQueryService.listFiles(OWNER_ID, null, "comic");
        var novels = fileQueryService.listFiles(OWNER_ID, null, "novel");
        var archives = fileQueryService.listFiles(OWNER_ID, null, "archive");
        var others = fileQueryService.listFiles(OWNER_ID, null, "other");

        assertThat(audios).extracting("name").containsExactly("song.mp3");
        assertThat(images).extracting("name").containsExactly("cover.jpg");
        assertThat(videos).extracting("name").containsExactly("clip.mkv");
        assertThat(documents).extracting("name").containsExactly("report.pdf");
        assertThat(comics).extracting("name").containsExactly("chapter.cbz");
        assertThat(novels).extracting("name").containsExactly("book.azw3");
        assertThat(archives).extracting("name").containsExactly("backup.zip");
        assertThat(others).extracting("name").containsExactly("raw.bin");
    }

    @Test
    void listFilesPageWithCategoryUsesDatabasePagingForRoot() {
        FileNode movie = node(OWNER_ID, null, "FILE", "movie.mp4", "/movie.mp4");
        movie.setMimeType("video/mp4");
        when(fileNodeRepository.findVisiblePersonalCategoryPage(
                eq(OWNER_ID), eq(SpaceType.PERSONAL), eq("video"),
                ArgumentMatchers.any(org.springframework.data.domain.Pageable.class)))
                .thenReturn(new org.springframework.data.domain.PageImpl<>(List.of(movie)));

        var page = fileQueryService.listFilesPage(OWNER_ID, null, "video", 0, 100);

        assertThat(page.getContent()).extracting("name").containsExactly("movie.mp4");
        verify(fileNodeRepository, never())
                .findByOwnerUserIdAndSpaceTypeAndDeletedFalse(OWNER_ID, SpaceType.PERSONAL);
    }

    @Test
    void listFilesPageWithCategoryUsesSubtreeQuery() {
        UUID folderId = UUID.fromString("30000000-0000-0000-0000-000000000004");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Media", "/Media");
        folder.setId(folderId);
        FileNode clip = node(OWNER_ID, folderId, "FILE", "clip.mkv", "/Media/clip.mkv");
        clip.setMimeType("application/octet-stream");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(folderId, OWNER_ID))
                .thenReturn(Optional.of(folder));
        when(fileNodeRepository.findVisibleSubtreeCategoryPage(
                eq(OWNER_ID), eq("/Media/"), eq("video"),
                ArgumentMatchers.any(org.springframework.data.domain.Pageable.class)))
                .thenReturn(new org.springframework.data.domain.PageImpl<>(List.of(clip)));

        var page = fileQueryService.listFilesPage(OWNER_ID, folderId, "video", 0, 50);

        assertThat(page.getContent()).extracting("name").containsExactly("clip.mkv");
        verify(fileNodeRepository, never())
                .findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedFalse(OWNER_ID, "/Media/");
    }

    @Test
    void createFolderRejectsPathTraversalName() {
        assertThatThrownBy(() -> fileQueryService.createFolder(OWNER_ID, new CreateFolderRequest(null, "../secret")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FILE_PATH_INVALID);
    }

    @Test
    void createFolderRejectsParentOwnedByAnotherUser() {
        UUID parentId = UUID.fromString("30000000-0000-0000-0000-000000000001");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(parentId, OWNER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> fileQueryService.createFolder(OWNER_ID, new CreateFolderRequest(parentId, "Docs")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FILE_NOT_FOUND);
    }

    @Test
    void createFolderReturnsNormalizedPath() {
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(OWNER_ID, "Docs"))
                .thenReturn(false);
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode node = invocation.getArgument(0);
                    node.setId(UUID.randomUUID());
                    return node;
                });

        var result = fileQueryService.createFolder(OWNER_ID, new CreateFolderRequest(null, "Docs"));

        assertThat(result.nodeType()).isEqualTo("FOLDER");
        assertThat(result.name()).isEqualTo("Docs");
        assertThat(result.normalizedPath()).isEqualTo("/Docs");
        ArgumentCaptor<SyncEventCommand> eventCaptor = ArgumentCaptor.forClass(SyncEventCommand.class);
        verify(syncEventRecorder).record(eventCaptor.capture());
        assertThat(eventCaptor.getValue().scope()).isEqualTo(SyncScope.FILES);
        assertThat(eventCaptor.getValue().action()).isEqualTo(SyncAction.CREATED);
    }

    @Test
    void renameNodeRejectsPathTraversalName() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000001");

        assertThatThrownBy(() -> fileQueryService.renameNode(OWNER_ID, fileId, new RenameFileNodeRequest("../secret")))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FILE_PATH_INVALID);
    }

    @Test
    void renameFolderUpdatesNodeAndDescendantPaths() {
        UUID folderId = UUID.fromString("40000000-0000-0000-0000-000000000002");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Docs", "/Docs");
        folder.setId(folderId);
        FileNode child = node(OWNER_ID, folderId, "FILE", "a.txt", "/Docs/a.txt");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(folderId, OWNER_ID))
                .thenReturn(Optional.of(folder));
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(OWNER_ID, "Archive"))
                .thenReturn(false);
        when(fileNodeRepository.findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedFalse(OWNER_ID, "/Docs/"))
                .thenReturn(List.of(child));
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var renamed = fileQueryService.renameNode(OWNER_ID, folderId, new RenameFileNodeRequest("Archive"));

        assertThat(renamed.name()).isEqualTo("Archive");
        assertThat(renamed.normalizedPath()).isEqualTo("/Archive");
        assertThat(child.getNormalizedPath()).isEqualTo("/Archive/a.txt");
    }

    @Test
    void moveNodeRejectsMovingFolderIntoDescendant() {
        UUID folderId = UUID.fromString("40000000-0000-0000-0000-000000000003");
        UUID childFolderId = UUID.fromString("40000000-0000-0000-0000-000000000004");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Docs", "/Docs");
        folder.setId(folderId);
        FileNode childFolder = node(OWNER_ID, folderId, "FOLDER", "Child", "/Docs/Child");
        childFolder.setId(childFolderId);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(folderId, OWNER_ID))
                .thenReturn(Optional.of(folder));
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(childFolderId, OWNER_ID))
                .thenReturn(Optional.of(childFolder));

        assertThatThrownBy(() -> fileQueryService.moveNode(OWNER_ID, folderId, new MoveFileNodeRequest(childFolderId)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不能移动到自身子目录");
    }

    @Test
    void deleteFolderMarksNodeAndDescendantsDeleted() {
        UUID folderId = UUID.fromString("40000000-0000-0000-0000-000000000005");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Docs", "/Docs");
        folder.setId(folderId);
        FileNode child = node(OWNER_ID, folderId, "FILE", "a.txt", "/Docs/a.txt");
        UUID childId = UUID.fromString("40000000-0000-0000-0000-000000000006");
        child.setId(childId);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(folderId, OWNER_ID))
                .thenReturn(Optional.of(folder));
        when(fileNodeRepository.findActiveIdsByPathPrefix(
                ArgumentMatchers.eq(OWNER_ID),
                ArgumentMatchers.eq("/Docs/"),
                ArgumentMatchers.any()
        )).thenReturn(new SliceImpl<>(List.of(childId)), new SliceImpl<>(List.of()));
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileQueryService.deleteNode(OWNER_ID, folderId);

        assertThat(folder.isDeleted()).isTrue();
        assertThat(folder.getDeletedBy()).isEqualTo(OWNER_ID);
        verify(fileNodeRepository).softDeleteIds(OWNER_ID, List.of(childId), folder.getDeletedAt());
    }

    @Test
    void deleteFolderPublishesDeletedNodeIdsForCrossModuleCleanup() {
        UUID folderId = UUID.fromString("40000000-0000-0000-0000-000000000015");
        UUID childId = UUID.fromString("40000000-0000-0000-0000-000000000016");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Media", "/Media");
        folder.setId(folderId);
        FileNode child = node(OWNER_ID, folderId, "FILE", "movie.mp4", "/Media/movie.mp4");
        child.setId(childId);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(folderId, OWNER_ID))
                .thenReturn(Optional.of(folder));
        when(fileNodeRepository.findActiveIdsByPathPrefix(
                ArgumentMatchers.eq(OWNER_ID),
                ArgumentMatchers.eq("/Media/"),
                ArgumentMatchers.any()
        )).thenReturn(new SliceImpl<>(List.of(childId)), new SliceImpl<>(List.of()));
        when(fileNodeRepository.save(any(FileNode.class))).thenAnswer(invocation -> invocation.getArgument(0));

        fileQueryService.deleteNode(OWNER_ID, folderId);

        ArgumentCaptor<FileNodesSoftDeletedEvent> captor = ArgumentCaptor.forClass(FileNodesSoftDeletedEvent.class);
        verify(eventPublisher, times(2)).publishEvent(captor.capture());
        assertThat(captor.getAllValues()).allSatisfy(event ->
                assertThat(event.ownerUserId()).isEqualTo(OWNER_ID));
        assertThat(captor.getAllValues().stream().flatMap(event -> event.fileNodeIds().stream()).toList())
                .containsExactlyInAnyOrder(folderId, childId);
    }

    @Test
    void listRecycleBinReturnsDeletedNodes() {
        FileNode deleted = node(OWNER_ID, null, "FILE", "old.txt", "/old.txt");
        deleted.setDeleted(true);
        deleted.setDeletedAt(Instant.parse("2026-05-19T00:00:00Z"));
        when(fileNodeRepository.findPersonalRecyclePage(
                eq(OWNER_ID), eq(SpaceType.PERSONAL),
                ArgumentMatchers.any(org.springframework.data.domain.Pageable.class)))
                .thenReturn(new org.springframework.data.domain.PageImpl<>(List.of(deleted)));

        var result = fileQueryService.listRecycleBinPage(OWNER_ID, SpaceType.PERSONAL, 0, 200);

        assertThat(result).extracting("name").containsExactly("old.txt");
    }

    @Test
    void restoreNodeRejectsSiblingNameConflict() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000006");
        FileNode deleted = node(OWNER_ID, null, "FILE", "old.txt", "/old.txt");
        deleted.setId(fileId);
        deleted.setDeleted(true);
        when(fileNodeRepository.findByIdAndOwnerUserId(fileId, OWNER_ID)).thenReturn(Optional.of(deleted));
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(OWNER_ID, "old.txt"))
                .thenReturn(true);

        assertThatThrownBy(() -> fileQueryService.restoreNode(OWNER_ID, fileId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.CONFLICT);
    }

    @Test
    void createDownloadUrlReturnsPresignedUrlForOwnedFile() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000007");
        UUID objectId = UUID.fromString("50000000-0000-0000-0000-000000000001");
        FileNode file = node(OWNER_ID, null, "FILE", "movie.mp4", "/movie.mp4");
        file.setId(fileId);
        file.setCurrentObjectId(objectId);
        FileObject object = new FileObject();
        object.setId(objectId);
        object.setBucketName("user-files");
        object.setObjectKey("users/1/movie.mp4");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, OWNER_ID)).thenReturn(Optional.of(file));
        when(fileObjectRepository.findById(objectId)).thenReturn(Optional.of(object));
        when(objectStorageClient.createDownloadUrl(ArgumentMatchers.any(), ArgumentMatchers.any()))
                .thenReturn(URI.create("http://minio/download"));

        var result = fileQueryService.createDownloadUrl(OWNER_ID, fileId);

        assertThat(result.fileName()).isEqualTo("movie.mp4");
        assertThat(result.downloadUrl()).isEqualTo("http://minio/download");
    }

    @Test
    void openOwnedFileContentReturnsAuthorizedObjectStream() throws Exception {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000008");
        UUID objectId = UUID.fromString("50000000-0000-0000-0000-000000000002");
        FileNode file = node(OWNER_ID, null, "FILE", "photo.jpg", "/photo.jpg");
        file.setId(fileId);
        file.setCurrentObjectId(objectId);
        FileObject object = new FileObject();
        object.setId(objectId);
        object.setBucketName("user-files");
        object.setObjectKey("users/1/photo.jpg");
        object.setMimeType("image/jpeg");
        object.setSizeBytes(4);
        ByteArrayInputStream input = new ByteArrayInputStream(new byte[]{1, 2, 3, 4});
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(fileObjectRepository.findById(objectId)).thenReturn(Optional.of(object));
        when(objectStorageClient.getObject(ArgumentMatchers.any())).thenReturn(input);

        try (var result = fileQueryService.openOwnedFileContent(OWNER_ID, fileId)) {
            assertThat(result.inputStream()).isSameAs(input);
            assertThat(result.fileName()).isEqualTo("photo.jpg");
            assertThat(result.sizeBytes()).isEqualTo(4);
            assertThat(result.mimeType()).isEqualTo("image/jpeg");
        }
    }

    @Test
    void openReadableFileContentAllowsSharedFileWithViewPermission() throws Exception {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000009");
        UUID objectId = UUID.fromString("50000000-0000-0000-0000-000000000003");
        FileNode file = node(OTHER_OWNER_ID, null, "FILE", "shared.jpg", "/shared.jpg");
        file.setId(fileId);
        file.setShared(true);
        file.setCurrentObjectId(objectId);
        FileObject object = new FileObject();
        object.setId(objectId);
        object.setBucketName("user-files");
        object.setObjectKey("users/2/shared.jpg");
        object.setMimeType("image/jpeg");
        object.setSizeBytes(3);
        ByteArrayInputStream input = new ByteArrayInputStream(new byte[]{1, 2, 3});
        when(fileNodeRepository.findByIdAndDeletedFalse(fileId)).thenReturn(Optional.of(file));
        when(filePermissionService.resolvePermission(fileId, OWNER_ID)).thenReturn(FilePermission.readOnly());
        when(fileObjectRepository.findById(objectId)).thenReturn(Optional.of(object));
        when(objectStorageClient.getObject(ArgumentMatchers.any())).thenReturn(input);

        try (var result = fileQueryService.openReadableFileContent(OWNER_ID, fileId)) {
            assertThat(result.inputStream()).isSameAs(input);
            assertThat(result.fileName()).isEqualTo("shared.jpg");
        }
    }

    @Test
    void openReadableFileContentRejectsSharedFileWithoutViewPermission() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000010");
        FileNode file = node(OTHER_OWNER_ID, null, "FILE", "private.jpg", "/private.jpg");
        file.setId(fileId);
        file.setShared(true);
        when(fileNodeRepository.findByIdAndDeletedFalse(fileId)).thenReturn(Optional.of(file));
        when(filePermissionService.resolvePermission(fileId, OWNER_ID)).thenReturn(FilePermission.denyAll());

        assertThatThrownBy(() -> fileQueryService.openReadableFileContent(OWNER_ID, fileId))
                .isInstanceOf(BusinessException.class)
                .hasMessage("无权查看文件");
    }

    // ==================== 批量操作测试 ====================

    @Test
    void batchDeleteNodesMarksNodesAndDescendantsDeleted() {
        UUID folderId = UUID.fromString("60000000-0000-0000-0000-000000000001");
        UUID childId = UUID.fromString("60000000-0000-0000-0000-000000000002");
        UUID fileId = UUID.fromString("60000000-0000-0000-0000-000000000003");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Docs", "/Docs");
        folder.setId(folderId);
        FileNode child = node(OWNER_ID, folderId, "FILE", "a.txt", "/Docs/a.txt");
        child.setId(childId);
        FileNode standalone = node(OWNER_ID, null, "FILE", "readme.md", "/readme.md");
        standalone.setId(fileId);
        when(fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(
                OWNER_ID, List.of(folderId, fileId)))
                .thenReturn(List.of(folder, standalone));
        when(fileNodeRepository.findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedFalse(
                OWNER_ID, "/Docs/"))
                .thenReturn(List.of(child));
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = fileQueryService.batchDeleteNodes(OWNER_ID, List.of(folderId, fileId));

        assertThat(folder.isDeleted()).isTrue();
        assertThat(child.isDeleted()).isTrue();
        assertThat(standalone.isDeleted()).isTrue();
        assertThat(folder.getDeletedBy()).isEqualTo(OWNER_ID);
        assertThat(child.getDeletedBy()).isEqualTo(OWNER_ID);
        assertThat(standalone.getDeletedBy()).isEqualTo(OWNER_ID);
        assertThat(result).hasSize(2);
        assertThat(result).extracting("name").containsExactlyInAnyOrder("Docs", "readme.md");
    }

    @Test
    void batchDeleteNodesPublishesSoftDeletedEvent() {
        UUID fileId = UUID.fromString("60000000-0000-0000-0000-000000000004");
        FileNode file = node(OWNER_ID, null, "FILE", "data.csv", "/data.csv");
        file.setId(fileId);
        when(fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(
                OWNER_ID, List.of(fileId)))
                .thenReturn(List.of(file));
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileQueryService.batchDeleteNodes(OWNER_ID, List.of(fileId));

        ArgumentCaptor<FileNodesSoftDeletedEvent> captor =
                ArgumentCaptor.forClass(FileNodesSoftDeletedEvent.class);
        verify(eventPublisher).publishEvent(captor.capture());
        assertThat(captor.getValue().ownerUserId()).isEqualTo(OWNER_ID);
        assertThat(captor.getValue().fileNodeIds()).containsExactly(fileId);
    }

    @Test
    void batchDeleteNodesReturnsEmptyWhenNoMatchingNodes() {
        when(fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(
                OWNER_ID, List.of(UUID.fromString("60000000-0000-0000-0000-000000000099"))))
                .thenReturn(List.of());

        var result = fileQueryService.batchDeleteNodes(
                OWNER_ID, List.of(UUID.fromString("60000000-0000-0000-0000-000000000099")));

        assertThat(result).isEmpty();
        verify(eventPublisher, never()).publishEvent(any());
    }

    @Test
    void batchRestoreNodesRestoresDeletedNodesAndDescendants() {
        UUID folderId = UUID.fromString("60000000-0000-0000-0000-000000000005");
        UUID childId = UUID.fromString("60000000-0000-0000-0000-000000000006");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Docs", "/Docs");
        folder.setId(folderId);
        folder.setDeleted(true);
        FileNode child = node(OWNER_ID, folderId, "FILE", "a.txt", "/Docs/a.txt");
        child.setId(childId);
        child.setDeleted(true);
        when(fileNodeRepository.findByIdAndOwnerUserId(folderId, OWNER_ID))
                .thenReturn(Optional.of(folder));
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, "Docs"))
                .thenReturn(false);
        when(fileNodeRepository.findByOwnerUserIdAndNormalizedPathStartingWithAndDeletedTrue(
                OWNER_ID, "/Docs/"))
                .thenReturn(List.of(child));
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = fileQueryService.batchRestoreNodes(OWNER_ID, List.of(folderId));

        assertThat(folder.isDeleted()).isFalse();
        assertThat(child.isDeleted()).isFalse();
        assertThat(result).hasSize(1);
        assertThat(result).extracting("name").containsExactly("Docs");
    }

    @Test
    void batchRestoreNodesPublishesRestoredEvent() {
        UUID fileId = UUID.fromString("60000000-0000-0000-0000-000000000007");
        FileNode file = node(OWNER_ID, null, "FILE", "old.txt", "/old.txt");
        file.setId(fileId);
        file.setDeleted(true);
        when(fileNodeRepository.findByIdAndOwnerUserId(fileId, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, "old.txt"))
                .thenReturn(false);
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileQueryService.batchRestoreNodes(OWNER_ID, List.of(fileId));

        ArgumentCaptor<FileNodesRestoredEvent> captor =
                ArgumentCaptor.forClass(FileNodesRestoredEvent.class);
        verify(eventPublisher).publishEvent(captor.capture());
        assertThat(captor.getValue().ownerUserId()).isEqualTo(OWNER_ID);
        assertThat(captor.getValue().fileNodeIds()).containsExactly(fileId);
    }

    @Test
    void batchRestoreNodesRejectsSiblingNameConflict() {
        UUID fileId = UUID.fromString("60000000-0000-0000-0000-000000000008");
        FileNode deleted = node(OWNER_ID, null, "FILE", "conflict.txt", "/conflict.txt");
        deleted.setId(fileId);
        deleted.setDeleted(true);
        when(fileNodeRepository.findByIdAndOwnerUserId(fileId, OWNER_ID))
                .thenReturn(Optional.of(deleted));
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, "conflict.txt"))
                .thenReturn(true);

        assertThatThrownBy(() -> fileQueryService.batchRestoreNodes(OWNER_ID, List.of(fileId)))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.CONFLICT);
    }

    @Test
    void batchMoveNodesMovesFilesToTargetFolder() {
        UUID targetFolderId = UUID.fromString("60000000-0000-0000-0000-000000000009");
        UUID fileId = UUID.fromString("60000000-0000-0000-0000-00000000000a");
        FileNode targetFolder = node(OWNER_ID, null, "FOLDER", "Archive", "/Archive");
        targetFolder.setId(targetFolderId);
        FileNode file = node(OWNER_ID, null, "FILE", "doc.pdf", "/doc.pdf");
        file.setId(fileId);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(targetFolderId, OWNER_ID))
                .thenReturn(Optional.of(targetFolder));
        when(fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(
                OWNER_ID, List.of(fileId)))
                .thenReturn(List.of(file));
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdAndNameAndDeletedFalse(
                OWNER_ID, targetFolderId, "doc.pdf"))
                .thenReturn(false);
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = fileQueryService.batchMoveNodes(OWNER_ID, List.of(fileId), targetFolderId);

        assertThat(file.getParentId()).isEqualTo(targetFolderId);
        assertThat(file.getNormalizedPath()).isEqualTo("/Archive/doc.pdf");
        assertThat(result).hasSize(1);
    }

    @Test
    void batchMoveNodesRejectsMovingFolderIntoDescendant() {
        UUID folderId = UUID.fromString("60000000-0000-0000-0000-00000000000b");
        UUID childFolderId = UUID.fromString("60000000-0000-0000-0000-00000000000c");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Docs", "/Docs");
        folder.setId(folderId);
        FileNode childFolder = node(OWNER_ID, folderId, "FOLDER", "Sub", "/Docs/Sub");
        childFolder.setId(childFolderId);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(childFolderId, OWNER_ID))
                .thenReturn(Optional.of(childFolder));
        when(fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(
                OWNER_ID, List.of(folderId)))
                .thenReturn(List.of(folder));

        assertThatThrownBy(() -> fileQueryService.batchMoveNodes(
                OWNER_ID, List.of(folderId), childFolderId))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不能移动到自身子目录");
    }

    @Test
    void batchMoveNodesRejectsNameConflictInTargetFolder() {
        UUID targetFolderId = UUID.fromString("60000000-0000-0000-0000-00000000000d");
        UUID fileId = UUID.fromString("60000000-0000-0000-0000-00000000000e");
        FileNode targetFolder = node(OWNER_ID, null, "FOLDER", "Archive", "/Archive");
        targetFolder.setId(targetFolderId);
        FileNode file = node(OWNER_ID, null, "FILE", "doc.pdf", "/doc.pdf");
        file.setId(fileId);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(targetFolderId, OWNER_ID))
                .thenReturn(Optional.of(targetFolder));
        when(fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(
                OWNER_ID, List.of(fileId)))
                .thenReturn(List.of(file));
        when(fileNodeRepository.existsByOwnerUserIdAndParentIdAndNameAndDeletedFalse(
                OWNER_ID, targetFolderId, "doc.pdf"))
                .thenReturn(true);

        assertThatThrownBy(() -> fileQueryService.batchMoveNodes(
                OWNER_ID, List.of(fileId), targetFolderId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.CONFLICT);
    }

    @Test
    void batchMoveNodesReturnsEmptyWhenNoMatchingNodes() {
        UUID targetFolderId = UUID.fromString("60000000-0000-0000-0000-00000000000f");
        FileNode targetFolder = node(OWNER_ID, null, "FOLDER", "Archive", "/Archive");
        targetFolder.setId(targetFolderId);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(targetFolderId, OWNER_ID))
                .thenReturn(Optional.of(targetFolder));
        when(fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(
                OWNER_ID, List.of(UUID.fromString("60000000-0000-0000-0000-000000000099"))))
                .thenReturn(List.of());

        var result = fileQueryService.batchMoveNodes(
                OWNER_ID,
                List.of(UUID.fromString("60000000-0000-0000-0000-000000000099")),
                targetFolderId);

        assertThat(result).isEmpty();
    }

    private FileNode node(UUID ownerId, UUID parentId, String type, String name, String normalizedPath) {
        FileNode node = new FileNode();
        node.setId(UUID.randomUUID());
        node.setOwnerUserId(ownerId == null ? OTHER_OWNER_ID : ownerId);
        node.setParentId(parentId);
        node.setNodeType(type);
        node.setName(name);
        node.setNormalizedPath(normalizedPath);
        return node;
    }
}
