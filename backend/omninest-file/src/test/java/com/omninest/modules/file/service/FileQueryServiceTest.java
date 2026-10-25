package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.common.error.BusinessException;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.dto.BatchItemResult;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.CreateFolderRequest;
import com.omninest.modules.file.dto.FileContentRange;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileMediaInfoDto;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.dto.MoveFileNodeRequest;
import com.omninest.modules.file.dto.RenameFileNodeRequest;
import com.omninest.modules.file.event.FileNodesDeletedEvent;
import com.omninest.modules.file.event.FileNodesRestoredEvent;
import com.omninest.modules.file.event.FileNodesSoftDeletedEvent;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.io.ByteArrayInputStream;
import java.net.URI;
import java.io.ByteArrayInputStream;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.ArgumentMatchers;
import org.mockito.Mockito;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;
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
    private final FileIndexSyncService fileIndexSyncService =
            Mockito.mock(FileIndexSyncService.class);
    private final FileLifecycleGuard fileLifecycleGuard = Mockito.mock(FileLifecycleGuard.class);
    private final UserSyncEventRecorder syncEventRecorder = Mockito.mock(UserSyncEventRecorder.class);
    private final SharedSpaceService sharedSpaceService = Mockito.mock(SharedSpaceService.class);
    private final SharedSpaceQuotaService sharedSpaceQuotaService =
            Mockito.mock(SharedSpaceQuotaService.class);
    private final TransactionTemplate transactionTemplate = transactionTemplate();
    private final MinioFileContentProvider minioFileContentProvider = new MinioFileContentProvider(
            fileObjectRepository,
            objectStorageClient
    );
    private final FileContentAccessService fileContentAccessService = new FileContentAccessService(
            List.of(minioFileContentProvider),
            fileNodeRepository,
            fileObjectRepository,
            new LocalContentAccessTokenService("test-local-content-secret")
    );
    private final FileShareRecipientAccessService shareRecipientAccessService =
            Mockito.mock(FileShareRecipientAccessService.class);
    private final FileDownloadService fileDownloadService = new FileDownloadService(
            fileNodeRepository,
            fileContentAccessService,
            sharedSpaceService,
            shareRecipientAccessService
    );
    private final FileNodeLookupSupport lookup = new FileNodeLookupSupport(fileNodeRepository);
    private final FileNodeDtoAssembler assembler = new FileNodeDtoAssembler(
            fileNodeRepository,
            userIds -> Map.of(),
            (owner, ids) -> Map.of()
    );
    private final FileListQueryService listQueryService = new FileListQueryService(
            fileNodeRepository, lookup, assembler);
    private final FileQueryService fileQueryService = newQueryService(
            newDownloadService(fileContentAccessService, new MediaProbeService()));

    private FileDownloadContentService newDownloadService(
            FileContentAccessService access, MediaProbeService probeService) {
        return new FileDownloadContentService(
                lookup,
                fileNodeRepository,
                access,
                sharedSpaceService,
                shareRecipientAccessService,
                fileDownloadService,
                probeService,
                new MediaProbeSourceStager(access)
        );
    }

    private FileQueryService newQueryService(FileDownloadContentService downloadService) {
        return new FileQueryService(
                fileNodeRepository,
                fileLifecycleGuard,
                eventPublisher,
                fileIndexSyncService,
                syncEventRecorder,
                sharedSpaceService,
                sharedSpaceQuotaService,
                transactionTemplate,
                new FilePathRewriter(fileNodeRepository),
                lookup,
                assembler,
                listQueryService,
                downloadService,
                new FileRestoreSupport(fileNodeRepository, lookup)
        );
    }

    private static TransactionTemplate transactionTemplate() {
        TransactionTemplate template = Mockito.mock(TransactionTemplate.class);
        Mockito.lenient().when(template.execute(Mockito.any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        return template;
    }

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
                .findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        OWNER_ID, SpaceType.PERSONAL, "/Media/");
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
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "Docs"))
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
    void createFolderAllowsNameOwnedBySharedSpaceRootFolder() {
        // 共享空间节点同样保留 owner_user_id：个人空间建同名根目录必须只按个人空间判冲突，
        // 否则导入阅读器默认目录会被 409「同级目录下已存在同名文件夹」拦下。
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "Reader"))
                .thenReturn(false);
        when(fileNodeRepository.existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                SpaceType.SHARED, "Reader"))
                .thenReturn(true);
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> {
                    FileNode node = invocation.getArgument(0);
                    node.setId(UUID.randomUUID());
                    return node;
                });

        var result = fileQueryService.createFolder(OWNER_ID, new CreateFolderRequest(null, "Reader"));

        assertThat(result.normalizedPath()).isEqualTo("/Reader");
        assertThat(result.spaceType()).isEqualTo(SpaceType.PERSONAL.getValue());
        verify(fileNodeRepository).existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "Reader");
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
    void renameNodeRejectsSharedSpaceNode() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-00000000000b");
        FileNode shared = node(OWNER_ID, null, "FILE", "shared.txt", "/shared.txt");
        shared.setId(fileId);
        shared.setSpaceType(SpaceType.SHARED);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, OWNER_ID))
                .thenReturn(Optional.of(shared));

        assertThatThrownBy(() -> fileQueryService.renameNode(
                OWNER_ID, fileId, new RenameFileNodeRequest("renamed.txt")))
                .isInstanceOfSatisfying(BusinessException.class,
                        exception -> assertThat(exception.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
        verify(fileNodeRepository, never()).save(ArgumentMatchers.any(FileNode.class));
    }

    @Test
    void moveNodeRejectsSharedSpaceNode() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-00000000000c");
        FileNode shared = node(OWNER_ID, null, "FILE", "shared.txt", "/shared.txt");
        shared.setId(fileId);
        shared.setSpaceType(SpaceType.SHARED);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, OWNER_ID))
                .thenReturn(Optional.of(shared));

        assertThatThrownBy(() -> fileQueryService.moveNode(
                OWNER_ID, fileId, new MoveFileNodeRequest(null)))
                .isInstanceOfSatisfying(BusinessException.class,
                        exception -> assertThat(exception.errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
        verify(fileNodeRepository, never()).save(ArgumentMatchers.any(FileNode.class));
    }

    @Test
    void batchMoveNodesRejectsSharedSpaceNodesPerItem() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-00000000000d");
        FileNode shared = node(OWNER_ID, null, "FILE", "shared.txt", "/shared.txt");
        shared.setId(fileId);
        shared.setSpaceType(SpaceType.SHARED);
        when(fileNodeRepository.findByOwnerUserIdAndIdInAndDeletedFalse(OWNER_ID, List.of(fileId)))
                .thenReturn(List.of(shared));

        List<BatchItemResult> results = fileQueryService.batchMoveNodes(OWNER_ID, List.of(fileId), null);

        assertThat(results).singleElement().satisfies(result -> {
            assertThat(result.status()).isEqualTo("FAILED");
            assertThat(result.errorCode()).isEqualTo(ErrorCode.FORBIDDEN.name());
        });
        verify(fileNodeRepository, never()).save(ArgumentMatchers.any(FileNode.class));
    }

    @Test
    void renameFolderUpdatesNodeAndDescendantPaths() {
        UUID folderId = UUID.fromString("40000000-0000-0000-0000-000000000002");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Docs", "/Docs");
        folder.setId(folderId);
        FileNode child = node(OWNER_ID, folderId, "FILE", "a.txt", "/Docs/a.txt");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(folderId, OWNER_ID))
                .thenReturn(Optional.of(folder));
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "Archive"))
                .thenReturn(false);
        when(fileNodeRepository.findPersonalSubtreeAfterId(
                ArgumentMatchers.eq(OWNER_ID), ArgumentMatchers.eq(SpaceType.PERSONAL),
                ArgumentMatchers.eq("/Docs/"), ArgumentMatchers.any(), ArgumentMatchers.any()))
                .thenReturn(List.of(child), List.of());
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var renamed = fileQueryService.renameNode(OWNER_ID, folderId, new RenameFileNodeRequest("Archive"));

        assertThat(renamed.name()).isEqualTo("Archive");
        assertThat(renamed.normalizedPath()).isEqualTo("/Archive");
        assertThat(child.getNormalizedPath()).isEqualTo("/Archive/a.txt");
        // 文件夹本身不入索引，但其下文件必须按新路径重建索引。
        verify(fileIndexSyncService).scheduleAfterCommit(OWNER_ID, List.of(child.getId()));
    }

    @Test
    void renameEscapesWildcardsWhenCollectingDescendantsButKeepsPathMathLiteral() {
        UUID folderId = UUID.fromString("40000000-0000-0000-0000-00000000000a");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "S01_E01", "/S01_E01");
        folder.setId(folderId);
        FileNode child = node(OWNER_ID, folderId, "FILE", "a.txt", "/S01_E01/a.txt");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(folderId, OWNER_ID))
                .thenReturn(Optional.of(folder));
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "Archive"))
                .thenReturn(false);
        // 前缀进 LIKE 必须带转义；未转义时 /S01XE01/ 这类兄弟目录会被一起改名。
        when(fileNodeRepository.findPersonalSubtreeAfterId(
                ArgumentMatchers.eq(OWNER_ID), ArgumentMatchers.eq(SpaceType.PERSONAL),
                ArgumentMatchers.eq("/S01\\_E01/"), ArgumentMatchers.any(), ArgumentMatchers.any()))
                .thenReturn(List.of(child), List.of());
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileQueryService.renameNode(OWNER_ID, folderId, new RenameFileNodeRequest("Archive"));

        verify(fileNodeRepository, times(2)).findPersonalSubtreeAfterId(
                ArgumentMatchers.eq(OWNER_ID), ArgumentMatchers.eq(SpaceType.PERSONAL),
                ArgumentMatchers.eq("/S01\\_E01/"), ArgumentMatchers.any(), ArgumentMatchers.any());
        // 子节点路径重写仍按原始 oldPath 定位，转义串不得进 substring。
        assertThat(child.getNormalizedPath()).isEqualTo("/Archive/a.txt");
    }

    @Test
    void moveFolderSchedulesDescendantFileIndexSync() {
        UUID folderId = UUID.fromString("40000000-0000-0000-0000-00000000000c");
        UUID targetFolderId = UUID.fromString("40000000-0000-0000-0000-00000000000d");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Docs", "/Docs");
        folder.setId(folderId);
        FileNode targetFolder = node(OWNER_ID, null, "FOLDER", "Archive", "/Archive");
        targetFolder.setId(targetFolderId);
        FileNode child = node(OWNER_ID, folderId, "FILE", "a.txt", "/Docs/a.txt");
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(folderId, OWNER_ID))
                .thenReturn(Optional.of(folder));
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(targetFolderId, OWNER_ID))
                .thenReturn(Optional.of(targetFolder));
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, targetFolderId, "Docs"))
                .thenReturn(false);
        when(fileNodeRepository.findPersonalSubtreeAfterId(
                ArgumentMatchers.eq(OWNER_ID), ArgumentMatchers.eq(SpaceType.PERSONAL),
                ArgumentMatchers.eq("/Docs/"), ArgumentMatchers.any(), ArgumentMatchers.any()))
                .thenReturn(List.of(child), List.of());
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileQueryService.moveNode(OWNER_ID, folderId, new MoveFileNodeRequest(targetFolderId));

        assertThat(child.getNormalizedPath()).isEqualTo("/Archive/Docs/a.txt");
        verify(fileIndexSyncService).scheduleAfterCommit(OWNER_ID, List.of(child.getId()));
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
                ArgumentMatchers.eq(SpaceType.PERSONAL),
                ArgumentMatchers.eq("/Docs/"),
                ArgumentMatchers.any()
        )).thenReturn(new SliceImpl<>(List.of(childId))).thenReturn(new SliceImpl<>(List.of()));
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
                ArgumentMatchers.eq(SpaceType.PERSONAL),
                ArgumentMatchers.eq("/Media/"),
                ArgumentMatchers.any()
        )).thenReturn(new SliceImpl<>(List.of(childId))).thenReturn(new SliceImpl<>(List.of()));
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
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "old.txt"))
                .thenReturn(true);

        assertThatThrownBy(() -> fileQueryService.restoreNode(OWNER_ID, fileId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.CONFLICT);
    }

    @Test
    void restoreNodeRecomputesPathFromRenamedParentAndCascadesToDescendants() {
        UUID parentId = UUID.fromString("40000000-0000-0000-0000-000000000030");
        UUID folderId = UUID.fromString("40000000-0000-0000-0000-000000000031");
        FileNode parent = node(OWNER_ID, null, "FOLDER", "Archive", "/Archive");
        parent.setId(parentId);
        FileNode folder = node(OWNER_ID, parentId, "FOLDER", "old", "/Docs/old");
        folder.setId(folderId);
        folder.setDeleted(true);
        FileNode child = node(OWNER_ID, folderId, "FILE", "a.txt", "/Docs/old/a.txt");
        child.setDeleted(true);
        when(fileNodeRepository.findByIdAndOwnerUserId(folderId, OWNER_ID)).thenReturn(Optional.of(folder));
        when(fileNodeRepository.findById(parentId)).thenReturn(Optional.of(parent));
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(parentId, OWNER_ID))
                .thenReturn(Optional.of(parent));
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, parentId, "old")).thenReturn(false);
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OWNER_ID, SpaceType.PERSONAL, "/Docs/old/")).thenReturn(List.of(child));
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileQueryService.restoreNode(OWNER_ID, folderId);

        // 父目录已改名为 /Archive：恢复出的子树必须整体落到新前缀，而不是旧 /Docs/old。
        assertThat(folder.getNormalizedPath()).isEqualTo("/Archive/old");
        assertThat(child.getNormalizedPath()).isEqualTo("/Archive/old/a.txt");
    }

    @Test
    void restoreNodeAllowsSharedSpaceDeleterAndRechargesSharedQuota() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000020");
        FileNode deleted = node(OTHER_OWNER_ID, null, "FILE", "movie.mkv", "/movie.mkv");
        deleted.setId(fileId);
        deleted.setSpaceType(SpaceType.SHARED);
        deleted.setUploadedBy(OTHER_OWNER_ID);
        deleted.setDeleted(true);
        deleted.setDeletedBy(OWNER_ID);
        deleted.setSizeBytes(4096L);
        when(fileNodeRepository.findByIdAndOwnerUserId(fileId, OWNER_ID)).thenReturn(Optional.empty());
        when(fileNodeRepository.findById(fileId)).thenReturn(Optional.of(deleted));
        when(sharedSpaceService.calculateRestoreSubtreeStats(deleted))
                .thenReturn(new SharedSpaceService.SubtreeStats(4096L, 1L));
        when(fileNodeRepository.existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                SpaceType.SHARED, "movie.mkv")).thenReturn(false);
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OTHER_OWNER_ID, SpaceType.SHARED, "/movie.mkv/")).thenReturn(List.of());
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        FileNodeDto result = fileQueryService.restoreNode(OWNER_ID, fileId);

        assertThat(result.name()).isEqualTo("movie.mkv");
        assertThat(deleted.isDeleted()).isFalse();
        assertThat(deleted.getDeletedBy()).isNull();
        verify(sharedSpaceService).validateSharedLifecycleOperator(OWNER_ID, deleted);
        verify(sharedSpaceQuotaService).checkQuota(4096L);
        verify(sharedSpaceQuotaService).increaseUsage(4096L, 1L);
        ArgumentCaptor<FileNodesRestoredEvent> captor =
                ArgumentCaptor.forClass(FileNodesRestoredEvent.class);
        verify(eventPublisher).publishEvent(captor.capture());
        assertThat(captor.getValue().ownerUserId()).isEqualTo(OTHER_OWNER_ID);
        assertThat(captor.getValue().fileNodeIds()).containsExactly(fileId);
    }

    @Test
    void restoreNodeRejectsSharedSpaceNonDeleterNonUploader() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000021");
        UUID memberId = UUID.fromString("90000000-0000-0000-0000-000000000001");
        FileNode deleted = node(OTHER_OWNER_ID, null, "FILE", "movie.mkv", "/movie.mkv");
        deleted.setId(fileId);
        deleted.setSpaceType(SpaceType.SHARED);
        deleted.setUploadedBy(OTHER_OWNER_ID);
        deleted.setDeleted(true);
        deleted.setDeletedBy(OWNER_ID);
        when(fileNodeRepository.findByIdAndOwnerUserId(fileId, memberId)).thenReturn(Optional.empty());
        when(fileNodeRepository.findById(fileId)).thenReturn(Optional.of(deleted));

        assertThatThrownBy(() -> fileQueryService.restoreNode(memberId, fileId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FILE_NOT_FOUND);
        verifyNoInteractions(sharedSpaceQuotaService);
    }

    @Test
    void restoreNodeRestoresDeletedAncestorChain() {
        UUID parentId = UUID.fromString("40000000-0000-0000-0000-000000000030");
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000031");
        FileNode parent = node(OWNER_ID, null, "FOLDER", "folder", "/folder");
        parent.setId(parentId);
        parent.setDeleted(true);
        parent.setDeletedBy(OWNER_ID);
        FileNode child = node(OWNER_ID, parentId, "FILE", "old.txt", "/folder/old.txt");
        child.setId(fileId);
        child.setDeleted(true);
        child.setDeletedBy(OWNER_ID);
        when(fileNodeRepository.findByIdAndOwnerUserId(fileId, OWNER_ID)).thenReturn(Optional.of(child));
        when(fileNodeRepository.findById(parentId)).thenReturn(Optional.of(parent));
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "folder")).thenReturn(false);
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, parentId, "old.txt")).thenReturn(false);
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OWNER_ID, SpaceType.PERSONAL, "/folder/old.txt/")).thenReturn(List.of());
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileQueryService.restoreNode(OWNER_ID, fileId);

        assertThat(parent.isDeleted()).isFalse();
        assertThat(child.isDeleted()).isFalse();
        ArgumentCaptor<FileNodesRestoredEvent> captor =
                ArgumentCaptor.forClass(FileNodesRestoredEvent.class);
        verify(eventPublisher).publishEvent(captor.capture());
        assertThat(captor.getValue().fileNodeIds()).containsExactlyInAnyOrder(parentId, fileId);
    }

    @Test
    void restoreNodePersonalSpaceKeepsOwnerScopeAndSkipsSharedLedger() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000022");
        FileNode deleted = node(OWNER_ID, null, "FILE", "old.txt", "/old.txt");
        deleted.setId(fileId);
        deleted.setDeleted(true);
        deleted.setDeletedBy(OWNER_ID);
        when(fileNodeRepository.findByIdAndOwnerUserId(fileId, OWNER_ID)).thenReturn(Optional.of(deleted));
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "old.txt")).thenReturn(false);
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OWNER_ID, SpaceType.PERSONAL, "/old.txt/")).thenReturn(List.of());
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        fileQueryService.restoreNode(OWNER_ID, fileId);

        assertThat(deleted.isDeleted()).isFalse();
        verifyNoInteractions(sharedSpaceService, sharedSpaceQuotaService);
        ArgumentCaptor<FileNodesRestoredEvent> captor =
                ArgumentCaptor.forClass(FileNodesRestoredEvent.class);
        verify(eventPublisher).publishEvent(captor.capture());
        assertThat(captor.getValue().ownerUserId()).isEqualTo(OWNER_ID);
    }

    @Test
    void batchRestoreNodesRestoresSharedTrashAndChargesSharedQuota() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000023");
        FileNode deleted = node(OTHER_OWNER_ID, null, "FILE", "clip.mp4", "/clip.mp4");
        deleted.setId(fileId);
        deleted.setSpaceType(SpaceType.SHARED);
        deleted.setUploadedBy(OTHER_OWNER_ID);
        deleted.setDeleted(true);
        deleted.setDeletedBy(OWNER_ID);
        deleted.setSizeBytes(2048L);
        when(fileNodeRepository.findByIdAndOwnerUserId(fileId, OWNER_ID)).thenReturn(Optional.empty());
        when(fileNodeRepository.findById(fileId)).thenReturn(Optional.of(deleted));
        when(sharedSpaceService.calculateRestoreSubtreeStats(deleted))
                .thenReturn(new SharedSpaceService.SubtreeStats(2048L, 1L));
        when(fileNodeRepository.existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                SpaceType.SHARED, "clip.mp4")).thenReturn(false);
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OTHER_OWNER_ID, SpaceType.SHARED, "/clip.mp4/")).thenReturn(List.of());
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = fileQueryService.batchRestoreNodes(OWNER_ID, List.of(fileId));

        assertThat(result).extracting("status").containsExactly("SUCCESS");
        assertThat(deleted.isDeleted()).isFalse();
        verify(sharedSpaceQuotaService).checkQuota(2048L);
        verify(sharedSpaceQuotaService).increaseUsage(2048L, 1L);
        ArgumentCaptor<FileNodesRestoredEvent> captor =
                ArgumentCaptor.forClass(FileNodesRestoredEvent.class);
        verify(eventPublisher).publishEvent(captor.capture());
        assertThat(captor.getValue().ownerUserId()).isEqualTo(OTHER_OWNER_ID);
        assertThat(captor.getValue().fileNodeIds()).containsExactly(fileId);
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
        file.setCurrentObjectId(objectId);
        FileObject object = new FileObject();
        object.setId(objectId);
        object.setBucketName("user-files");
        object.setObjectKey("users/2/shared.jpg");
        object.setMimeType("image/jpeg");
        object.setSizeBytes(3);
        ByteArrayInputStream input = new ByteArrayInputStream(new byte[]{1, 2, 3});
        when(fileNodeRepository.findByIdAndDeletedFalse(fileId)).thenReturn(Optional.of(file));
        when(shareRecipientAccessService.canAccessRecipientNode(OWNER_ID, file)).thenReturn(true);
        when(fileObjectRepository.findById(objectId)).thenReturn(Optional.of(object));
        when(objectStorageClient.getObject(ArgumentMatchers.any())).thenReturn(input);

        try (var result = fileQueryService.openReadableFileContent(OWNER_ID, fileId)) {
            assertThat(result.inputStream()).isSameAs(input);
            assertThat(result.fileName()).isEqualTo("shared.jpg");
        }
    }

    @Test
    void createReadableDownloadUrlRequiresSharedDownloadPermission() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000011");
        FileNode file = node(OTHER_OWNER_ID, null, "FILE", "book.epub", "/book.epub");
        file.setId(fileId);
        file.setSpaceType(SpaceType.SHARED);
        when(fileNodeRepository.findByIdAndDeletedFalse(fileId)).thenReturn(Optional.of(file));
        when(sharedSpaceService.canBrowse(OWNER_ID)).thenReturn(true);
        when(sharedSpaceService.canDownload(OWNER_ID)).thenReturn(false);

        assertThatThrownBy(() -> fileQueryService.createReadableDownloadUrl(OWNER_ID, fileId))
                .isInstanceOf(BusinessException.class)
                .hasMessage("无权下载该文件");
    }

    @Test
    void openReadableFileContentRejectsSharedFileWithoutViewPermission() {
        UUID fileId = UUID.fromString("40000000-0000-0000-0000-000000000010");
        FileNode file = node(OTHER_OWNER_ID, null, "FILE", "private.jpg", "/private.jpg");
        file.setId(fileId);
        when(fileNodeRepository.findByIdAndDeletedFalse(fileId)).thenReturn(Optional.of(file));
        when(shareRecipientAccessService.canAccessRecipientNode(OWNER_ID, file)).thenReturn(false);

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
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "/Docs/"))
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
        assertThat(result).extracting("status").containsOnly("SUCCESS");
        assertThat(result).extracting("id").containsExactlyInAnyOrder(folderId, fileId);
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

        assertThat(result).extracting("status").containsExactly("SKIPPED");
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
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "Docs"))
                .thenReturn(false);
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OWNER_ID, SpaceType.PERSONAL, "/Docs/"))
                .thenReturn(List.of(child));
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = fileQueryService.batchRestoreNodes(OWNER_ID, List.of(folderId));

        assertThat(folder.isDeleted()).isFalse();
        assertThat(child.isDeleted()).isFalse();
        assertThat(result).hasSize(1);
        assertThat(result).extracting("status").containsExactly("SUCCESS");
        assertThat(result).extracting("id").containsExactly(folderId);
    }

    @Test
    void batchRestoreNodesRestoresRemainingSiblingsWhenChildIsListedFirst() {
        UUID folderId = UUID.fromString("60000000-0000-0000-0000-000000000030");
        UUID childId = UUID.fromString("60000000-0000-0000-0000-000000000031");
        UUID siblingId = UUID.fromString("60000000-0000-0000-0000-000000000032");
        FileNode folder = node(OWNER_ID, null, "FOLDER", "Docs", "/Docs");
        folder.setId(folderId);
        folder.setDeleted(true);
        FileNode child = node(OWNER_ID, folderId, "FILE", "a.txt", "/Docs/a.txt");
        child.setId(childId);
        child.setDeleted(true);
        FileNode sibling = node(OWNER_ID, folderId, "FILE", "c.txt", "/Docs/c.txt");
        sibling.setId(siblingId);
        sibling.setDeleted(true);
        when(fileNodeRepository.findByIdAndOwnerUserId(folderId, OWNER_ID)).thenReturn(Optional.of(folder));
        when(fileNodeRepository.findByIdAndOwnerUserId(childId, OWNER_ID)).thenReturn(Optional.of(child));
        when(fileNodeRepository.findById(folderId)).thenReturn(Optional.of(folder));
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "Docs")).thenReturn(false);
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, folderId, "a.txt")).thenReturn(false);
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OWNER_ID, SpaceType.PERSONAL, "/Docs/a.txt/")).thenReturn(List.of());
        when(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedTrue(
                OWNER_ID, SpaceType.PERSONAL, "/Docs/")).thenReturn(List.of(child, sibling));
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = fileQueryService.batchRestoreNodes(OWNER_ID, List.of(childId, folderId));

        assertThat(result).extracting("status").containsExactly("SUCCESS", "SUCCESS");
        assertThat(folder.isDeleted()).isFalse();
        assertThat(child.isDeleted()).isFalse();
        assertThat(sibling.isDeleted()).isFalse();
    }

    @Test
    void batchRestoreNodesChargesSharedQuotaAgainstAccumulatedBatchBytes() {
        UUID firstId = UUID.fromString("60000000-0000-0000-0000-000000000033");
        UUID secondId = UUID.fromString("60000000-0000-0000-0000-000000000034");
        long eightyMegabytes = 80L * 1024 * 1024;
        FileNode first = node(OTHER_OWNER_ID, null, "FILE", "a.mp4", "/a.mp4");
        first.setId(firstId);
        first.setSpaceType(SpaceType.SHARED);
        first.setUploadedBy(OTHER_OWNER_ID);
        first.setDeleted(true);
        first.setDeletedBy(OWNER_ID);
        first.setSizeBytes(eightyMegabytes);
        FileNode second = node(OTHER_OWNER_ID, null, "FILE", "b.mp4", "/b.mp4");
        second.setId(secondId);
        second.setSpaceType(SpaceType.SHARED);
        second.setUploadedBy(OTHER_OWNER_ID);
        second.setDeleted(true);
        second.setDeletedBy(OWNER_ID);
        second.setSizeBytes(eightyMegabytes);
        when(fileNodeRepository.findByIdAndOwnerUserId(firstId, OWNER_ID)).thenReturn(Optional.empty());
        when(fileNodeRepository.findByIdAndOwnerUserId(secondId, OWNER_ID)).thenReturn(Optional.empty());
        when(fileNodeRepository.findById(firstId)).thenReturn(Optional.of(first));
        when(fileNodeRepository.findById(secondId)).thenReturn(Optional.of(second));
        when(sharedSpaceService.calculateRestoreSubtreeStats(first))
                .thenReturn(new SharedSpaceService.SubtreeStats(eightyMegabytes, 1L));
        when(sharedSpaceService.calculateRestoreSubtreeStats(second))
                .thenReturn(new SharedSpaceService.SubtreeStats(eightyMegabytes, 1L));
        when(fileNodeRepository.existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                SpaceType.SHARED, "a.mp4")).thenReturn(false);
        when(fileNodeRepository.existsBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                SpaceType.SHARED, "b.mp4")).thenReturn(false);
        Mockito.doAnswer(invocation -> {
            long requested = invocation.getArgument(0);
            if (requested > 100L * 1024 * 1024) {
                throw new BusinessException(ErrorCode.FILE_QUOTA_EXCEEDED, "共享空间容量不足");
            }
            return null;
        }).when(sharedSpaceQuotaService).checkQuota(anyLong());
        when(fileNodeRepository.saveAll(ArgumentMatchers.anyList()))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = fileQueryService.batchRestoreNodes(OWNER_ID, List.of(firstId, secondId));

        assertThat(result).extracting("status").containsExactly("SUCCESS", "FAILED");
        assertThat(first.isDeleted()).isFalse();
        assertThat(second.isDeleted()).isTrue();
        verify(sharedSpaceQuotaService).checkQuota(eightyMegabytes);
        verify(sharedSpaceQuotaService).checkQuota(eightyMegabytes * 2);
        verify(sharedSpaceQuotaService).increaseUsage(eightyMegabytes, 1L);
        verify(sharedSpaceQuotaService, never()).increaseUsage(eightyMegabytes * 2, 2L);
    }

    @Test
    void batchRestoreNodesPublishesRestoredEvent() {
        UUID fileId = UUID.fromString("60000000-0000-0000-0000-000000000007");
        FileNode file = node(OWNER_ID, null, "FILE", "old.txt", "/old.txt");
        file.setId(fileId);
        file.setDeleted(true);
        when(fileNodeRepository.findByIdAndOwnerUserId(fileId, OWNER_ID))
                .thenReturn(Optional.of(file));
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "old.txt"))
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
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, "conflict.txt"))
                .thenReturn(true);

        var conflictResult = fileQueryService.batchRestoreNodes(OWNER_ID, List.of(fileId));
        assertThat(conflictResult).extracting("status").containsExactly("FAILED");
        assertThat(conflictResult).extracting("errorCode").containsExactly("CONFLICT");
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
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, targetFolderId, "doc.pdf"))
                .thenReturn(false);
        when(fileNodeRepository.save(ArgumentMatchers.any(FileNode.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        var result = fileQueryService.batchMoveNodes(OWNER_ID, List.of(fileId), targetFolderId);

        assertThat(file.getParentId()).isEqualTo(targetFolderId);
        assertThat(file.getNormalizedPath()).isEqualTo("/Archive/doc.pdf");
        assertThat(result).hasSize(1);
        assertThat(result.get(0).status()).isEqualTo("SUCCESS");
        verify(fileIndexSyncService).scheduleAfterCommit(OWNER_ID, List.of(fileId));
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

        var moveResult = fileQueryService.batchMoveNodes(OWNER_ID, List.of(folderId), childFolderId);
        assertThat(moveResult).extracting("status").containsExactly("FAILED");
        assertThat(moveResult).extracting("errorCode").containsExactly("FILE_PATH_INVALID");
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
        when(fileNodeRepository.existsByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse(
                OWNER_ID, SpaceType.PERSONAL, targetFolderId, "doc.pdf"))
                .thenReturn(true);

        var nameConflictResult = fileQueryService.batchMoveNodes(OWNER_ID, List.of(fileId), targetFolderId);
        assertThat(nameConflictResult).extracting("status").containsExactly("FAILED");
        assertThat(nameConflictResult).extracting("errorCode").containsExactly("CONFLICT");
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

        assertThat(result).extracting("status").containsExactly("SKIPPED");
    }

    /**
     * 探测输入形态是这条链的安全边界：交出预签名地址后，媒体内容里内嵌的远程引用会被
     * ffprobe 自己跟随，那批地址不受任何校验。这里反向钉住"不索取下载地址"。
     */
    @Test
    void mediaInfoNeverHandsFfprobeAPresignedAddress() {
        UUID fileId = UUID.fromString("70000000-0000-0000-0000-000000000001");
        UUID objectId = UUID.fromString("70000000-0000-0000-0000-000000000002");
        FileNode video = node(OWNER_ID, null, "FILE", "clip.mp4", "/clip.mp4");
        video.setMimeType("video/mp4");
        video.setCurrentObjectId(objectId);
        FileObject object = new FileObject();
        object.setId(objectId);
        object.setBucketName("user-files");
        object.setObjectKey("users/1/clip.mp4");
        object.setMimeType("video/mp4");
        object.setSizeBytes(4096L);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, OWNER_ID))
                .thenReturn(Optional.of(video));
        when(fileObjectRepository.findById(objectId)).thenReturn(Optional.of(object));
        when(objectStorageClient.getObject(any(ObjectStorageKey.class)))
                .thenReturn(new ByteArrayInputStream(new byte[4096]));

        FileMediaInfoDto info = fileQueryService.mediaInfo(OWNER_ID, fileId);

        assertThat(info.isEmpty()).isTrue();
        verify(objectStorageClient, never()).createDownloadUrl(any(ObjectStorageKey.class), any(Duration.class));
        verify(objectStorageClient, never()).getObject(any(ObjectStorageKey.class), anyLong(), anyLong());
    }

    /**
     * 非 faststart 的对象把容器索引放在尾窗之外时，默认窗只能回空；
     * 这里验的是"确实再放大一档重试一次"，且两档用不同缓存键（否则会读回第一档缓存的空结果）。
     */
    @Test
    void mediaInfoEscalatesTailWindowWhenIndexFallsOutside() {
        FileContentAccessService access = Mockito.mock(FileContentAccessService.class);
        MediaProbeService probeService = Mockito.mock(MediaProbeService.class);
        FileQueryService service = newQueryService(newDownloadService(access, probeService));

        UUID fileId = UUID.fromString("80000000-0000-0000-0000-000000000001");
        UUID objectId = UUID.fromString("80000000-0000-0000-0000-000000000002");
        long headBytes = 2L * 1024 * 1024;
        long total = 12L * 1024 * 1024;
        FileNode video = node(OWNER_ID, null, "FILE", "long.mp4", "/long.mp4");
        video.setMimeType("video/mp4");
        video.setCurrentObjectId(objectId);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, OWNER_ID))
                .thenReturn(Optional.of(video));
        when(access.open(video)).thenReturn(new FileContentStream(
                new ByteArrayInputStream(new byte[(int) headBytes]), "long.mp4", total, "video/mp4"));
        when(access.openRange(ArgumentMatchers.<FileNode>any(), ArgumentMatchers.anyLong(),
                ArgumentMatchers.anyLong()))
                .thenAnswer(invocation -> {
                    long length = invocation.getArgument(2);
                    return Optional.of(new FileContentRange(
                            new ByteArrayInputStream(new byte[(int) length]), total));
                });

        String narrowKey = objectId + ":tail=" + MediaProbeSourceStager.DEFAULT_TAIL_BYTES;
        String wideKey = objectId + ":tail=" + MediaProbeSourceStager.ESCALATED_TAIL_BYTES;
        when(probeService.probe(ArgumentMatchers.eq(narrowKey), ArgumentMatchers.any()))
                .thenReturn(new FileMediaInfoDto(null, null, null));
        when(probeService.probe(ArgumentMatchers.eq(wideKey), ArgumentMatchers.any()))
                .thenReturn(new FileMediaInfoDto(5400.0, 1920, 1080));

        FileMediaInfoDto info = service.mediaInfo(OWNER_ID, fileId);

        assertThat(info.width()).isEqualTo(1920);
        assertThat(info.durationSeconds()).isEqualTo(5400.0);
        verify(probeService).probe(ArgumentMatchers.eq(narrowKey), ArgumentMatchers.any());
        verify(probeService).probe(ArgumentMatchers.eq(wideKey), ArgumentMatchers.any());
    }

    /**
     * 第一档就拿到元数据时不得再放大窗口，否则每次探测都多读 32 MiB。
     */
    @Test
    void mediaInfoDoesNotEscalateWhenDefaultWindowSuffices() {
        FileContentAccessService access = Mockito.mock(FileContentAccessService.class);
        MediaProbeService probeService = Mockito.mock(MediaProbeService.class);
        FileQueryService service = newQueryService(newDownloadService(access, probeService));

        UUID fileId = UUID.fromString("80000000-0000-0000-0000-000000000003");
        UUID objectId = UUID.fromString("80000000-0000-0000-0000-000000000004");
        long headBytes = 2L * 1024 * 1024;
        long total = 12L * 1024 * 1024;
        FileNode video = node(OWNER_ID, null, "FILE", "fast.mp4", "/fast.mp4");
        video.setMimeType("video/mp4");
        video.setCurrentObjectId(objectId);
        when(fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, OWNER_ID))
                .thenReturn(Optional.of(video));
        when(access.open(video)).thenReturn(new FileContentStream(
                new ByteArrayInputStream(new byte[(int) headBytes]), "fast.mp4", total, "video/mp4"));
        when(access.openRange(ArgumentMatchers.<FileNode>any(), ArgumentMatchers.anyLong(),
                ArgumentMatchers.anyLong()))
                .thenAnswer(invocation -> Optional.of(new FileContentRange(
                        new ByteArrayInputStream(new byte[(int) (long) invocation.getArgument(2)]), total)));
        when(probeService.probe(ArgumentMatchers.anyString(), ArgumentMatchers.any()))
                .thenReturn(new FileMediaInfoDto(60.0, 1280, 720));

        assertThat(service.mediaInfo(OWNER_ID, fileId).height()).isEqualTo(720);
        verify(probeService, times(1)).probe(ArgumentMatchers.anyString(), ArgumentMatchers.any());
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
