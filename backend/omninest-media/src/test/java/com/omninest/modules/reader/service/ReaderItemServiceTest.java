package com.omninest.modules.reader.service;
import com.omninest.modules.media.config.MediaProcessingLimitsProperties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.access.SharedSpaceAccessQuery;
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
import com.omninest.modules.reader.domain.ReaderItemSource;
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
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.mockito.ArgumentCaptor;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.multipart.MultipartFile;

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
    private SharedSpaceAccessQuery sharedSpaceAccessQuery;
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

    @BeforeEach
    void allowSharedSpaceVisibility() {
        lenient().when(sharedSpaceAccessQuery.canBrowse(OWNER_ID)).thenReturn(true);
    }

    @Test
    @DisplayName("元数据编辑写入并读回出版日期、评分、标签、连载状态与 ISBN")
    void updateMetadataPersistsAndReturnsEveryEditableField() {
        // 编辑页有五个字段后端 DTO 根本不接收：保存提示成功，字段静默丢弃，重载又变回去
        ReaderItem item = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "书名", "EPUB");
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(itemRepository.save(item)).thenReturn(item);

        itemService.updateMetadata(OWNER_ID, ITEM_ID, new UpdateItemMetadataRequest(
                "书名二",
                "作者",
                "简介",
                "出版社",
                "zh-CN",
                LocalDate.of(2024, 5, 1),
                new BigDecimal("8.50"),
                List.of(" 科幻 ", "漫画", " "),
                "SERIALIZING",
                "978-7-000-0000-0"));

        assertThat(item.getTitle()).isEqualTo("书名二");
        assertThat(item.getReleaseDate()).isEqualTo(LocalDate.of(2024, 5, 1));
        assertThat(item.getRating()).isEqualByComparingTo("8.50");
        assertThat(item.getGenres()).containsEntry("items", List.of("科幻", "漫画"));
        assertThat(item.getExternalIds())
                .containsEntry("serialStatus", "SERIALIZING")
                .containsEntry("isbn", "978-7-000-0000-0");

        ReaderItemDto dto = itemService.toDto(item, false);
        assertThat(dto.releaseDate()).isEqualTo(LocalDate.of(2024, 5, 1));
        assertThat(dto.rating()).isEqualByComparingTo("8.50");
        assertThat(dto.genres()).containsExactly("科幻", "漫画");
        assertThat(dto.serialStatus()).isEqualTo("SERIALIZING");
        assertThat(dto.isbn()).isEqualTo("978-7-000-0000-0");
    }

    @Test
    void deleteItemCleansItsOwnDerivedCover() {
        // 派生封面不在网盘里，任何清理任务都不会再枚举它：随条目删除时必须一起走，
        // 否则每次删书都在数据库与对象存储里留一个孤儿节点。
        ReaderItem item = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "Book With Cover", "TXT");
        item.setCoverFileId(COVER_FILE_NODE_ID);
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of());
        when(pageAssetRepository.findByReaderItemIdIn(List.of(ITEM_ID))).thenReturn(List.of());
        when(itemRepository.findByCoverFileIdIn(List.of(COVER_FILE_NODE_ID))).thenReturn(List.of(item));

        itemService.deleteItem(OWNER_ID, ITEM_ID);

        verify(derivedAssetStorageService).deleteDerivedFileNode(COVER_FILE_NODE_ID);
    }

    @Test
    void deleteItemKeepsCoverThatAnotherItemStillReferences() {
        ReaderItem item = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "Duplicated Book", "TXT");
        item.setCoverFileId(COVER_FILE_NODE_ID);
        ReaderItem sibling = newItem(
                UUID.fromString("20000000-0000-0000-0000-000000000009"),
                OWNER_ID,
                FILE_NODE_ID,
                "Same Content",
                "TXT"
        );
        sibling.setCoverFileId(COVER_FILE_NODE_ID);
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of());
        when(pageAssetRepository.findByReaderItemIdIn(List.of(ITEM_ID))).thenReturn(List.of());
        when(itemRepository.findByCoverFileIdIn(List.of(COVER_FILE_NODE_ID)))
                .thenReturn(List.of(item, sibling));

        itemService.deleteItem(OWNER_ID, ITEM_ID);

        verify(derivedAssetStorageService, never()).deleteDerivedFileNode(any());
    }

    @Test
    void uploadCoverDeletesReplacedDerivedCover() {
        UUID previousCoverId = UUID.fromString("30000000-0000-0000-0000-000000000005");
        UUID newCoverId = UUID.fromString("30000000-0000-0000-0000-000000000006");
        ReaderItem item = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "Covered Book", "EPUB");
        item.setCoverFileId(previousCoverId);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(derivedAssetStorageService.store(
                any(), any(), any(), any(), any(), any(), any(java.io.InputStream.class)
        )).thenReturn(newCoverId);
        when(itemRepository.findByCoverFileIdIn(List.of(previousCoverId))).thenReturn(List.of(item));

        itemService.uploadCover(OWNER_ID, ITEM_ID, pngUpload("封面.png"));

        assertThat(item.getCoverFileId()).isEqualTo(newCoverId);
        verify(derivedAssetStorageService).deleteDerivedFileNode(previousCoverId);
    }

    @Test
    void uploadCoverKeepsNodeWhenDerivedStorageReusesIt() {
        // 同一路径的派生存储会原地复用同一个 FileNode：把"被替换的旧封面"删掉，
        // 等于把刚写好的那张一起删，条目只剩指向空对象的节点。
        UUID sameCoverId = UUID.fromString("30000000-0000-0000-0000-000000000007");
        ReaderItem item = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "Covered Book", "EPUB");
        item.setCoverFileId(sameCoverId);
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.of(item));
        when(derivedAssetStorageService.store(
                any(), any(), any(), any(), any(), any(), any(java.io.InputStream.class)
        )).thenReturn(sameCoverId);

        itemService.uploadCover(OWNER_ID, ITEM_ID, pngUpload("封面.png"));

        verify(derivedAssetStorageService, never()).deleteDerivedFileNode(any());
    }

    private MultipartFile pngUpload(String fileName) {
        MultipartFile file = mock(MultipartFile.class);
        when(file.isEmpty()).thenReturn(false);
        when(file.getSize()).thenReturn(64L);
        when(file.getOriginalFilename()).thenReturn(fileName);
        return file;
    }

    @Test
    void listItemsPageIncludesSharedSpaceItems() {
        // 用户个人条目 + 共享空间条目均可见
        ReaderItem personalItem = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "My Book", "TXT");
        ReaderItem sharedItem = newItem(SHARED_ITEM_ID, OTHER_USER_ID, SHARED_FILE_NODE_ID, "Shared Book", "TXT");
        Pageable pageable = PageRequest.of(0, 20);
        when(itemRepository.findVisibleItemsPage(
                eq(OWNER_ID), eq(SpaceType.SHARED), eq(""), eq(""), eq(""), eq(false), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(personalItem, sharedItem), pageable, 2));
        ReaderBookshelf shelfEntry = new ReaderBookshelf();
        shelfEntry.setReaderItemId(ITEM_ID);
        when(bookshelfRepository.findByOwnerUserIdAndReaderItemIdIn(OWNER_ID, List.of(ITEM_ID, SHARED_ITEM_ID)))
                .thenReturn(List.of(shelfEntry));

        List<ReaderItemDto> result = itemService
                .listItemsPage(OWNER_ID, null, null, null, false, 0, 20)
                .getContent();

        assertThat(result).hasSize(2);
        assertThat(result.get(0).title()).isEqualTo("My Book");
        assertThat(result.get(0).addedToBookshelf()).isTrue();
        assertThat(result.get(0).fileNodeId()).isEqualTo(FILE_NODE_ID);
        assertThat(result.get(1).title()).isEqualTo("Shared Book");
        assertThat(result.get(1).addedToBookshelf()).isFalse();
        assertThat(result.get(1).fileNodeId()).isEqualTo(SHARED_FILE_NODE_ID);
    }

    @Test
    void listItemsPageExcludesSharedSpaceWhenBrowseDenied() {
        when(sharedSpaceAccessQuery.canBrowse(OWNER_ID)).thenReturn(false);
        when(itemRepository.findVisibleItemsPage(
                eq(OWNER_ID), isNull(), eq(""), eq(""), eq(""), eq(false), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of()));

        itemService.listItemsPage(OWNER_ID, null, null, null, false, 0, 20);

        verify(itemRepository).findVisibleItemsPage(
                eq(OWNER_ID), isNull(), eq(""), eq(""), eq(""), eq(false), any(Pageable.class));
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
                null,
                null,
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
    void updateMetadataAsAdminRejectsOtherUsersPersonalItem() {
        ReaderItem personal = newItem(
                SHARED_ITEM_ID, OTHER_USER_ID, SHARED_FILE_NODE_ID, "Private Book", "TXT");
        when(itemRepository.findById(SHARED_ITEM_ID)).thenReturn(Optional.of(personal));
        when(fileMetadataQueryService.findById(SHARED_FILE_NODE_ID)).thenReturn(Optional.of(
                newFileDescriptor(SHARED_FILE_NODE_ID, SpaceType.PERSONAL, "private.txt", null)));
        UpdateItemMetadataRequest request = new UpdateItemMetadataRequest(
                "Changed", null, null, null, null, null, null, null, null, null);

        assertThatThrownBy(() -> itemService.updateMetadataAsAdmin(OWNER_ID, SHARED_ITEM_ID, request))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("阅读条目不存在");
        verify(itemRepository, never()).save(any());
    }

    @Test
    void updateMetadataAsAdminAllowsOtherUsersSharedItem() {
        ReaderItem shared = newItem(
                SHARED_ITEM_ID, OTHER_USER_ID, SHARED_FILE_NODE_ID, "Shared Book", "TXT");
        when(itemRepository.findById(SHARED_ITEM_ID)).thenReturn(Optional.of(shared));
        when(fileMetadataQueryService.findById(SHARED_FILE_NODE_ID)).thenReturn(Optional.of(
                newFileDescriptor(SHARED_FILE_NODE_ID, SpaceType.SHARED, "shared.txt", null)));
        UpdateItemMetadataRequest request = new UpdateItemMetadataRequest(
                "Changed", null, null, null, null, null, null, null, null, null);

        itemService.updateMetadataAsAdmin(OWNER_ID, SHARED_ITEM_ID, request);

        assertThat(shared.getTitle()).isEqualTo("Changed");
        verify(itemRepository).save(shared);
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

    /**
     * 多卷作品的源文件是全部卷：只提交主卷会让其余分卷留在网盘，清理参与者看到还有分卷存活
     * 就只抽走一卷并把主文件迁到下一卷，作品删不掉。
     */
    @Test
    @SuppressWarnings("unchecked")
    void cascadeDeleteSubmitsEveryOwnedVolumeOfAComic() {
        UUID secondVolumeId = UUID.fromString("20000000-0000-0000-0000-0000000000a1");
        UUID thirdVolumeId = UUID.fromString("20000000-0000-0000-0000-0000000000a2");
        UUID foreignVolumeId = UUID.fromString("20000000-0000-0000-0000-0000000000a3");
        ReaderItem item = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "多卷漫画", "CBZ");
        item.setContentKind("COMIC");
        when(itemRepository.findByIdAndOwnerUserId(ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of(
                newSourceItem(secondVolumeId),
                newSourceItem(thirdVolumeId),
                newSourceItem(foreignVolumeId)));
        when(fileMetadataQueryService.findById(secondVolumeId)).thenReturn(Optional.of(
                newFileDescriptor(secondVolumeId, SpaceType.PERSONAL, "v2.cbz", null)));
        when(fileMetadataQueryService.findById(thirdVolumeId)).thenReturn(Optional.of(
                newFileDescriptor(thirdVolumeId, SpaceType.PERSONAL, "v3.cbz", null)));
        when(fileMetadataQueryService.findById(foreignVolumeId)).thenReturn(Optional.of(
                newOwnedFileDescriptor(foreignVolumeId, "v4.cbz", OTHER_USER_ID)));

        itemService.deleteItem(OWNER_ID, ITEM_ID, true);

        ArgumentCaptor<List<UUID>> submitted = ArgumentCaptor.forClass(List.class);
        verify(fileDeletionService).deletePermanentlyBatch(
                eq(OWNER_ID), submitted.capture(), eq(true), anyList());
        assertThat(submitted.getValue()).containsExactlyInAnyOrder(FILE_NODE_ID, secondVolumeId, thirdVolumeId);
        verify(fileDeletionService, never()).deletePermanently(
                eq(OWNER_ID), any(UUID.class), eq(true), any(FilePurgeOrigin.class), isNull());
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

    /** 创建归属指定用户的文件节点描述符。 */
    private FileDescriptor newOwnedFileDescriptor(UUID id, String name, UUID ownerUserId) {
        return new FileDescriptor(
                id,
                ownerUserId,
                null,
                "FILE",
                name,
                "/" + name,
                "application/octet-stream",
                0,
                null,
                "UPLOAD",
                false,
                false,
                SpaceType.PERSONAL,
                ownerUserId,
                null,
                null
        );
    }

    /** 创建漫画分卷来源行。 */
    private ReaderItemSource newSourceItem(UUID fileNodeId) {
        ReaderItemSource source = new ReaderItemSource();
        source.setId(UUID.randomUUID());
        source.setReaderItemId(ITEM_ID);
        source.setFileNodeId(fileNodeId);
        return source;
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

    @Test
    void listItemsPageSlicesFilteredItemsAndClampsOverflow() {
        ReaderItem a = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "Book A", "TXT");
        ReaderItem b = newItem(SHARED_ITEM_ID, OWNER_ID, SHARED_FILE_NODE_ID, "Book B", "TXT");
        ReaderItem c = newItem(UUID.fromString("30000000-0000-0000-0000-000000000003"), OWNER_ID, UUID.fromString("40000000-0000-0000-0000-000000000003"), "Book C", "TXT");
        List<ReaderItem> all = List.of(a, b, c);
        when(itemRepository.findVisibleItemsPage(
                eq(OWNER_ID), eq(SpaceType.SHARED), any(), any(), any(), eq(false), any(Pageable.class)))
                .thenAnswer(invocation -> {
                    Pageable pageable = invocation.getArgument(6);
                    int from = (int) Math.min((long) pageable.getPageNumber() * pageable.getPageSize(),
                            all.size());
                    int to = Math.min(from + pageable.getPageSize(), all.size());
                    return new PageImpl<>(all.subList(from, to), pageable, all.size());
                });
        when(bookshelfRepository.findByOwnerUserIdAndReaderItemIdIn(any(), any()))
                .thenReturn(List.of());

        var first = itemService.listItemsPage(OWNER_ID, null, null, null, false, 0, 2);
        var second = itemService.listItemsPage(OWNER_ID, null, null, null, false, 1, 2);
        var overflow = itemService.listItemsPage(OWNER_ID, null, null, null, false, 9, 2);

        assertThat(first.getContent()).extracting(ReaderItemDto::title)
                .containsExactly("Book A", "Book B");
        assertThat(second.getContent()).extracting(ReaderItemDto::title)
                .containsExactly("Book C");
        assertThat(first.getTotalElements()).isEqualTo(3);
        assertThat(second.getTotalElements()).isEqualTo(3);
        assertThat(overflow.getContent()).isEmpty();
        assertThat(overflow.getTotalElements()).isEqualTo(3);
    }

    /**
     * 书架分页必须先按书架过滤再切片：否则一页里可能一个书架条目都没有，
     * 前端只能盲目续拉，总数也会算进未加架条目。
     */
    @Test
    void listItemsPageWithBookshelfOnlySlicesShelfItemsAndCountsShelfTotal() {
        ReaderItem a = newItem(ITEM_ID, OWNER_ID, FILE_NODE_ID, "Book A", "TXT");
        ReaderItem b = newItem(SHARED_ITEM_ID, OWNER_ID, SHARED_FILE_NODE_ID, "Book B", "TXT");
        ReaderItem c = newItem(
                UUID.fromString("30000000-0000-0000-0000-000000000003"),
                OWNER_ID,
                UUID.fromString("40000000-0000-0000-0000-000000000003"),
                "Book C",
                "TXT");
        Pageable pageable = PageRequest.of(0, 2);
        when(itemRepository.findVisibleItemsPage(
                eq(OWNER_ID), eq(SpaceType.SHARED), any(), any(), any(), eq(true), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(c), pageable, 1));

        var only = itemService.listItemsPage(OWNER_ID, null, null, null, true, 0, 2);

        assertThat(only.getContent()).extracting(ReaderItemDto::title).containsExactly("Book C");
        assertThat(only.getContent()).allSatisfy(dto -> assertThat(dto.addedToBookshelf()).isTrue());
        assertThat(only.getTotalElements()).isEqualTo(1);
    }

}
