package com.omninest.modules.reader.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.dto.FileDownloadUrlDto;
import com.omninest.modules.file.service.FileContentAccessService;
import com.omninest.modules.file.service.DerivedAssetStorageService;
import com.omninest.modules.file.service.FileDeletionService;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FilePurgeOrigin;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.photos.service.PhotoInputGuard;
import com.omninest.modules.reader.domain.ReaderAnnotation;
import com.omninest.modules.reader.domain.ReaderBookmark;
import com.omninest.modules.reader.domain.ReaderBookshelf;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderNote;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.dto.ReaderDtos.ReaderItemDto;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateItemMetadataRequest;
import com.omninest.modules.reader.repository.ReaderAnnotationRepository;
import com.omninest.modules.reader.repository.ReaderBookmarkRepository;
import com.omninest.modules.reader.repository.ReaderBookshelfRepository;
import com.omninest.modules.reader.repository.ReaderCatalogNodeRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderNoteRepository;
import com.omninest.modules.reader.repository.ReaderPageAssetRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.repository.ReaderProgressRepository;
import com.omninest.modules.reader.repository.ReaderReadingSessionRepository;
import com.omninest.modules.reader.repository.ReaderTextChapterRepository;
import com.omninest.modules.task.service.TaskRecordService;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 阅读条目服务单元测试：验证共享空间可见性、权限校验与级联删除。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderItemServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OTHER_USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000099");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SHARED_ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000003");
    private static final UUID FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID SHARED_FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000003");
    private static final UUID COVER_FILE_NODE_ID = UUID.fromString(
            "30000000-0000-0000-0000-000000000004"
    );

    @Mock
    private ReaderItemRepository itemRepository;
    @Mock
    private ReaderProgressRepository progressRepository;
    @Mock
    private ReaderBookshelfRepository bookshelfRepository;
    @Mock
    private ReaderBookmarkRepository bookmarkRepository;
    @Mock
    private ReaderAnnotationRepository annotationRepository;
    @Mock
    private ReaderNoteRepository noteRepository;
    @Mock
    private ReaderReadingSessionRepository sessionRepository;
    @Mock
    private ReaderItemSourceRepository sourceRepository;
    @Mock
    private ReaderCatalogNodeRepository catalogRepository;
    @Mock
    private ReaderPageRepository pageRepository;
    @Mock
    private ReaderPageAssetRepository pageAssetRepository;
    @Mock
    private ReaderTextChapterRepository textChapterRepository;
    @Mock
    private FileMetadataQueryService fileMetadataQueryService;
    @Mock
    private FileQueryService fileQueryService;
    @Mock
    private FileContentAccessService fileContentAccessService;
    @Mock
    private FileDeletionService fileDeletionService;
    @Mock
    private FileLifecycleGuard fileLifecycleGuard;
    @Mock
    private DerivedAssetStorageService derivedAssetStorageService;
    @Mock
    private MediaSyncEventService syncEventService;
    @Mock
    private TaskRecordService taskRecordService;
    @Mock
    private PhotoInputGuard photoInputGuard;

    @org.mockito.Spy
    private MediaProcessingLimitsProperties processingLimits = new MediaProcessingLimitsProperties();

    @InjectMocks
    private ReaderItemService itemService;

    @Test
    void listItemsIncludesSharedSpaceItems() {
        // 用户个人条目 + 共享空间条目均可见
        ReaderItem personalItem = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "My Book", "TXT");
        ReaderItem sharedItem = newItem(SHARED_ITEM_ID, OTHER_USER_ID, SHARED_FILE_NODE_ID, "Shared Book", "TXT");

        when(itemRepository.findItemsVisibleToUser(OWNER_ID, SpaceType.SHARED))
                .thenReturn(List.of(personalItem, sharedItem));
        // listItems 使用批量查询书架状态
        ReaderBookshelf shelfEntry = new ReaderBookshelf();
        shelfEntry.setReaderItemId(ITEM_ID);
        when(bookshelfRepository.findByOwnerUserIdAndReaderItemIdIn(OWNER_ID, List.of(ITEM_ID, SHARED_ITEM_ID)))
                .thenReturn(List.of(shelfEntry));

        List<ReaderItemDto> result = itemService.listItems(OWNER_ID, null, null, null);

        assertThat(result).hasSize(2);
        assertThat(result.get(0).title()).isEqualTo("My Book");
        assertThat(result.get(0).addedToBookshelf()).isTrue();
        assertThat(result.get(1).title()).isEqualTo("Shared Book");
        assertThat(result.get(1).addedToBookshelf()).isFalse();
    }

    @Test
    void requireItemAllowsSharedSpaceAccess() {
        // 条目属于其他用户，但文件在共享空间 → 允许访问
        ReaderItem sharedItem = newItem(SHARED_ITEM_ID, OTHER_USER_ID, SHARED_FILE_NODE_ID, "Shared Book", "TXT");

        FileDescriptor sharedFileNode = newFileDescriptor(
                SHARED_FILE_NODE_ID, SpaceType.SHARED, "shared.txt", null);

        when(itemRepository.findById(SHARED_ITEM_ID)).thenReturn(Optional.of(sharedItem));
        when(fileLifecycleGuard.requireReadable(OWNER_ID, SHARED_FILE_NODE_ID)).thenReturn(sharedFileNode);
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, SHARED_ITEM_ID)).thenReturn(false);

        var result = itemService.getItemDetail(OWNER_ID, SHARED_ITEM_ID);

        assertThat(result.item().title()).isEqualTo("Shared Book");
    }

    @Test
    void requireItemRejectsPersonalFileFromOtherUser() {
        // 条目属于其他用户的个人空间 → 拒绝访问
        ReaderItem otherItem = newItem(ITEM_ID, OTHER_USER_ID, FILE_NODE_ID, "Private Book", "TXT");

        FileDescriptor personalFileNode = newFileDescriptor(
                FILE_NODE_ID, SpaceType.PERSONAL, "private.txt", null);

        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(otherItem));
        when(fileLifecycleGuard.requireReadable(OWNER_ID, FILE_NODE_ID))
                .thenThrow(new BusinessException(ErrorCode.FORBIDDEN, "无权查看文件"));

        assertThatThrownBy(() -> itemService.getItemDetail(OWNER_ID, ITEM_ID))
                .isInstanceOf(BusinessException.class)
                .satisfies(ex -> assertThat(((BusinessException) ex).errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
    }

    @Test
    void requireOwnedItemAllowsOwnerWithWritableSource() {
        ReaderItem item = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "Owned Book", "TXT");
        FileDescriptor file = newFileDescriptor(FILE_NODE_ID, SpaceType.PERSONAL, "book.txt", null);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(fileLifecycleGuard.requireOwnedWritable(OWNER_ID, FILE_NODE_ID)).thenReturn(file);

        assertThat(itemService.requireOwnedItem(OWNER_ID, ITEM_ID)).isSameAs(item);
    }

    @Test
    void updateMetadataRejectsSharedReadableItemOwnedByAnotherUser() {
        ReaderItem sharedItem = newItem(
                SHARED_ITEM_ID,
                OTHER_USER_ID,
                SHARED_FILE_NODE_ID,
                "Shared Book",
                "TXT"
        );
        when(itemRepository.findById(SHARED_ITEM_ID)).thenReturn(Optional.of(sharedItem));
        UpdateItemMetadataRequest request = new UpdateItemMetadataRequest(
                "Changed",
                null,
                null,
                null,
                null
        );

        assertThatThrownBy(() -> itemService.updateMetadata(OWNER_ID, SHARED_ITEM_ID, request))
                .isInstanceOf(BusinessException.class)
                .satisfies(exception -> assertThat(((BusinessException) exception).errorCode())
                        .isEqualTo(ErrorCode.FORBIDDEN));

        verify(itemRepository, never()).save(any());
        verify(fileLifecycleGuard, never()).requireOwnedWritable(OWNER_ID, SHARED_FILE_NODE_ID);
    }

    @Test
    void deleteItemRemovesLibraryRecordAndRetainsOwnedSourceFileByDefault() {
        ReaderItem item = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "Book To Delete", "TXT");
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of());
        when(pageAssetRepository.findByReaderItemIdIn(List.of(ITEM_ID))).thenReturn(List.of());

        itemService.deleteItem(OWNER_ID, ITEM_ID);

        verify(itemRepository).delete(item);
        verify(fileDeletionService, never()).deletePermanently(
                eq(OWNER_ID), eq(FILE_NODE_ID), eq(false), any(FilePurgeOrigin.class), isNull());
    }

    @Test
    void cascadeDeletePermanentlyDeletesOwnedSourceFile() {
        ReaderItem item = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "Book To Delete", "TXT");
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));

        itemService.deleteItem(OWNER_ID, ITEM_ID, true);

        verify(fileDeletionService).deletePermanently(
                eq(OWNER_ID), eq(FILE_NODE_ID), eq(true), any(FilePurgeOrigin.class), isNull());
    }

    @Test
    void deleteItemRejectsSharedItemOwnedByAnotherUser() {
        when(itemRepository.findByIdAndOwnerUserId(SHARED_ITEM_ID, OWNER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> itemService.deleteItem(OWNER_ID, SHARED_ITEM_ID))
                .isInstanceOf(BusinessException.class)
                .satisfies(exception -> assertThat(((BusinessException) exception).errorCode())
                        .isEqualTo(ErrorCode.BOOK_NOT_FOUND));

        verify(fileDeletionService, never()).deletePermanently(
                eq(OWNER_ID),
                eq(SHARED_FILE_NODE_ID),
                eq(false),
                any(FilePurgeOrigin.class),
                isNull()
        );
    }

    @Test
    void createFileTicketReturnsSignedMetadataWithoutReadingObject() {
        ReaderItem item = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "Large Book", "EPUB");
        UUID objectId = UUID.fromString("50000000-0000-0000-0000-000000000001");
        FileDescriptor fileNode = newFileDescriptor(
                FILE_NODE_ID,
                SpaceType.PERSONAL,
                "original.epub",
                objectId,
                2L * 1024 * 1024 * 1024,
                "application/epub+zip"
        );

        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(fileLifecycleGuard.requireReadable(OWNER_ID, FILE_NODE_ID)).thenReturn(fileNode);
        when(fileMetadataQueryService.findContentSha256(FILE_NODE_ID)).thenReturn(Optional.of("abc123"));
        when(fileQueryService.createReadableDownloadUrl(OWNER_ID, FILE_NODE_ID))
                .thenReturn(new FileDownloadUrlDto(
                        FILE_NODE_ID,
                        "original.epub",
                        "https://storage.example/large-book.epub?signature=test",
                        Instant.parse("2026-06-12T00:15:00Z")
                ));

        var ticket = itemService.createFileTicket(OWNER_ID, ITEM_ID);

        assertThat(ticket.itemId()).isEqualTo(ITEM_ID);
        assertThat(ticket.fileName()).isEqualTo("Large Book.epub");
        assertThat(ticket.sizeBytes()).isEqualTo(2L * 1024 * 1024 * 1024);
        assertThat(ticket.sha256()).isEqualTo("abc123");
        assertThat(ticket.downloadUrl()).contains("signature=test");
        verify(fileQueryService).createReadableDownloadUrl(OWNER_ID, FILE_NODE_ID);
    }

    @Test
    void prepareCoverDownloadReturnsMetadataWithoutReadingObject() {
        ReaderItem item = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "Large Book", "EPUB");
        item.setCoverFileId(COVER_FILE_NODE_ID);
        UUID objectId = UUID.fromString("50000000-0000-0000-0000-000000000002");
        FileDescriptor coverFile = newFileDescriptor(
                COVER_FILE_NODE_ID,
                SpaceType.PERSONAL,
                "cover.webp",
                objectId,
                4L * 1024 * 1024,
                "image/webp"
        );

        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(fileLifecycleGuard.requireReadable(OWNER_ID, FILE_NODE_ID))
                .thenReturn(newFileDescriptor(FILE_NODE_ID, SpaceType.PERSONAL, "original.epub", null));
        when(fileMetadataQueryService.findById(COVER_FILE_NODE_ID)).thenReturn(Optional.of(coverFile));
        when(fileMetadataQueryService.findContentSha256(COVER_FILE_NODE_ID))
                .thenReturn(Optional.of("cover-hash"));

        ReaderItemService.DownloadDescriptor descriptor = itemService.prepareCoverDownload(
                OWNER_ID,
                ITEM_ID
        );

        assertThat(descriptor.fileNodeId()).isEqualTo(COVER_FILE_NODE_ID);
        assertThat(descriptor.fileName()).isEqualTo("cover.webp");
        assertThat(descriptor.sizeBytes()).isEqualTo(4L * 1024 * 1024);
        assertThat(descriptor.sha256()).isEqualTo("cover-hash");
        assertThat(descriptor.contentType()).isEqualTo("image/webp");
        assertThat(descriptor.mediaAsset()).isTrue();
    }

    @Test
    void streamFileTransfersObjectWithoutBuildingByteArray() throws Exception {
        ReaderItemService.DownloadDescriptor descriptor = new ReaderItemService.DownloadDescriptor(
                OWNER_ID,
                FILE_NODE_ID,
                "book.txt",
                4,
                "hash",
                "text/plain",
                false
        );
        when(fileQueryService.openReadableFileContent(OWNER_ID, FILE_NODE_ID))
                .thenReturn(new FileContentStream(
                        new ByteArrayInputStream(new byte[]{1, 2, 3, 4}),
                        "book.txt",
                        4,
                        "text/plain"
                ));
        try (ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {
            itemService.streamFile(descriptor, outputStream);
            assertThat(outputStream.toByteArray()).containsExactly(1, 2, 3, 4);
        }
    }

    // ==================== 辅助方法 ====================

    /** 创建阅读条目实例。 */
    private ReaderItem newItem(UUID id, UUID ownerUserId, UUID fileNodeId, String title, String itemType) {
        ReaderItem item = new ReaderItem();
        item.setId(id);
        item.setOwnerUserId(ownerUserId);
        item.setFileNodeId(fileNodeId);
        item.setTitle(title);
        item.setItemType(itemType);
        item.setContentKind("TEXT");
        item.setCreatedAt(Instant.parse("2026-06-12T00:00:00Z"));
        item.setUpdatedAt(Instant.parse("2026-06-12T00:00:00Z"));
        return item;
    }

    /** 创建文件节点描述符。 */
    private FileDescriptor newFileDescriptor(UUID id, SpaceType spaceType, String name, UUID currentObjectId) {
        return newFileDescriptor(id, spaceType, name, currentObjectId, 0, "application/octet-stream");
    }

    /** 创建带内容元数据的文件节点描述符。 */
    private FileDescriptor newFileDescriptor(
            UUID id,
            SpaceType spaceType,
            String name,
            UUID currentObjectId,
            long sizeBytes,
            String mimeType
    ) {
        return new FileDescriptor(
                id,
                OWNER_ID,
                null,
                "FILE",
                name,
                "/" + name,
                mimeType,
                sizeBytes,
                currentObjectId,
                "UPLOAD",
                false,
                false,
                spaceType,
                OWNER_ID,
                null,
                null
        );
    }
}
