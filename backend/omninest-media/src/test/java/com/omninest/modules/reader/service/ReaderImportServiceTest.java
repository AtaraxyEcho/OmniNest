package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.sync.SyncScope;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FileQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderBookshelf;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderSourceStatus;
import com.omninest.modules.reader.event.ComicParseTaskEvent;
import com.omninest.modules.reader.repository.ReaderBookshelfRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 阅读导入服务单元测试：验证内容哈希去重、空间隔离、跨用户分卷合并与权限校验。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderImportServiceTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID OTHER_USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000099");
    private static final UUID FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID FILE_OBJECT_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");
    private static final UUID SAVED_ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID EXISTING_ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000002");
    private static final UUID DUP_FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000002");
    private static final UUID SOURCE_ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000003");
    private static final byte[] FILE_BYTES = "Hello, world!".getBytes(StandardCharsets.UTF_8);

    @Mock
    private ReaderItemRepository itemRepository;
    @Mock
    private ReaderBookshelfRepository bookshelfRepository;
    @Mock
    private FileMetadataQueryService fileMetadataQueryService;
    @Mock
    private FileQueryService fileQueryService;
    @Mock
    private ReaderFileDetector fileDetector;
    @Mock
    private ReaderComicManifestService comicManifestService;
    @Mock
    private ReaderItemSourceRepository sourceRepository;
    @Mock
    private TaskRecordService taskRecordService;
    @Mock
    private TaskDispatchService taskDispatchService;
    @Mock
    private ReaderTextParseSubmissionService textParseSubmissionService;
    @Mock
    private ReaderPdfMetadataService pdfMetadataService;
    @Mock
    private ReaderCoverExtractionService coverExtractionService;
    @Mock
    private MediaSyncEventService syncEventService;
    @Mock
    private TransactionTemplate transactionTemplate;

    @InjectMocks
    private ReaderImportService importService;

    /**
     * 导入把大文件哈希与版式探测挪到事务外后，落库段经 TransactionTemplate 执行，
     * 桩必须真的回调业务体，否则每个用例都拿不到条目。
     */
    @BeforeEach
    @SuppressWarnings("unchecked")
    void runTransactionCallback() {
        lenient().when(transactionTemplate.execute(any())).thenAnswer(invocation ->
                ((TransactionCallback<Object>) invocation.getArgument(0)).doInTransaction(null));
    }

    @Test
    void importCreatesItemAndAddsToBookshelf() {
        // 同一用户首次导入 TXT 文件
        ReaderItem savedItem = new ReaderItem();
        savedItem.setId(SAVED_ITEM_ID);

        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(personalFileNode("book.txt")));
        stubReadFileBytes();
        when(fileDetector.detectType("book.txt")).thenReturn("TXT");
        when(itemRepository.save(any(ReaderItem.class))).thenReturn(savedItem);
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, SAVED_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID);

        assertThat(result.getId()).isEqualTo(SAVED_ITEM_ID);
        ArgumentCaptor<ReaderItem> itemCaptor = ArgumentCaptor.forClass(ReaderItem.class);
        verify(itemRepository).save(itemCaptor.capture());
        assertThat(itemCaptor.getValue().getOwnerUserId()).isEqualTo(OWNER_ID);
        assertThat(itemCaptor.getValue().getFileNodeId()).isEqualTo(FILE_NODE_ID);
        assertThat(itemCaptor.getValue().getItemType()).isEqualTo("TXT");
        verify(bookshelfRepository).save(any(ReaderBookshelf.class));
    }

    @Test
    void importTextBookSubmitsParseTask() {
        // 文本书籍导入后必须提交文本解析任务，避免卡在 PARSING
        ReaderItem savedItem = new ReaderItem();
        savedItem.setId(SAVED_ITEM_ID);

        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(personalFileNode("book.txt")));
        stubReadFileBytes();
        when(fileDetector.detectType("book.txt")).thenReturn("TXT");
        when(itemRepository.save(any(ReaderItem.class))).thenReturn(savedItem);
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, SAVED_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));

        importService.importFile(OWNER_ID, FILE_NODE_ID);

        ArgumentCaptor<ReaderItem> submitCaptor = ArgumentCaptor.forClass(ReaderItem.class);
        verify(textParseSubmissionService).submit(submitCaptor.capture(), eq(false));
        assertThat(submitCaptor.getValue().getId()).isEqualTo(SAVED_ITEM_ID);
        verify(taskDispatchService, never()).enqueue(any(), any(), any(), any());
    }

    @Test
    void importExistingFileOnlyAddsToBookshelf() {
        // 同一用户再次导入相同文件 → 不创建新条目，仅加入书架
        ReaderItem existingItem = comicItem(EXISTING_ITEM_ID, OWNER_ID, FILE_NODE_ID, "书");
        existingItem.setContentKind("TEXT");

        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(personalFileNode("book.txt")));
        when(fileDetector.detectType("book.txt")).thenReturn("TXT");
        when(itemRepository.findAccessibleByFileNodeId(OWNER_ID, FILE_NODE_ID, SpaceType.SHARED))
                .thenReturn(List.of(existingItem));
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, EXISTING_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID);

        assertThat(result.getId()).isEqualTo(EXISTING_ITEM_ID);
        verify(bookshelfRepository).save(any(ReaderBookshelf.class));
        verify(itemRepository, never()).save(any());
    }

    @Test
    void importReusesSharedItemOwnedByAnotherUserWhenSameFileIsVisible() {
        // 共享空间的同一文件由他人建过条目：再次导入要回到那个作品，而不是每人一条
        ReaderItem sharedItem = comicItem(EXISTING_ITEM_ID, OTHER_USER_ID, FILE_NODE_ID, "共享书");
        sharedItem.setContentKind("TEXT");

        when(fileMetadataQueryService.findById(FILE_NODE_ID))
                .thenReturn(Optional.of(sharedFileNode("book.txt", OTHER_USER_ID)));
        when(fileDetector.detectType("book.txt")).thenReturn("TXT");
        when(itemRepository.findAccessibleByFileNodeId(OWNER_ID, FILE_NODE_ID, SpaceType.SHARED))
                .thenReturn(List.of(sharedItem));
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, EXISTING_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID);

        assertThat(result.getId()).isEqualTo(EXISTING_ITEM_ID);
        verify(itemRepository, never()).save(any());
    }

    @Test
    void importReusesWorkThatAlreadyHasThisFileAsAttachedVolume() {
        // 该文件已作为别人的多卷漫画分卷并入作品：再点导入应回到所属作品
        ReaderItem parent = comicItem(SOURCE_ITEM_ID, OTHER_USER_ID, DUP_FILE_NODE_ID, "系列");
        ReaderItemSource attached = new ReaderItemSource();
        attached.setReaderItemId(SOURCE_ITEM_ID);
        attached.setFileNodeId(FILE_NODE_ID);

        when(fileMetadataQueryService.findById(FILE_NODE_ID))
                .thenReturn(Optional.of(sharedFileNode("系列 第02卷.cbz", OWNER_ID)));
        when(fileDetector.detectType("系列 第02卷.cbz")).thenReturn("CBZ");
        when(sourceRepository.findByFileNodeIdIn(List.of(FILE_NODE_ID))).thenReturn(List.of(attached));
        when(itemRepository.findById(SOURCE_ITEM_ID)).thenReturn(Optional.of(parent));
        when(fileMetadataQueryService.findById(DUP_FILE_NODE_ID))
                .thenReturn(Optional.of(sharedFileNode(DUP_FILE_NODE_ID, "系列 第01卷.cbz", OTHER_USER_ID)));
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, SOURCE_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID);

        assertThat(result.getId()).isEqualTo(SOURCE_ITEM_ID);
        verify(itemRepository, never()).save(any());
    }

    @Test
    void importExistingEpubWithComicOverrideUpgradesAndQueuesParsing() {
        ReaderItem existingItem = comicItem(EXISTING_ITEM_ID, OWNER_ID, FILE_NODE_ID, "画册");
        existingItem.setContentKind("TEXT");
        existingItem.setContentHash(sha256(FILE_BYTES));

        when(itemRepository.findAccessibleByFileNodeId(OWNER_ID, FILE_NODE_ID, SpaceType.SHARED))
                .thenReturn(List.of(existingItem));
        when(itemRepository.findByIdForUpdate(EXISTING_ITEM_ID)).thenReturn(Optional.of(existingItem));
        when(fileMetadataQueryService.findById(FILE_NODE_ID))
                .thenReturn(Optional.of(personalFileNode("画册.epub")));
        when(fileDetector.detectType("画册.epub")).thenReturn("EPUB");
        when(itemRepository.save(existingItem)).thenReturn(existingItem);
        when(sourceRepository.findByReaderItemIdAndFileNodeId(EXISTING_ITEM_ID, FILE_NODE_ID))
                .thenReturn(Optional.empty());
        when(sourceRepository.save(any(ReaderItemSource.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, EXISTING_ITEM_ID)).thenReturn(true);

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID, false, "COMIC");

        assertThat(result.getContentKind()).isEqualTo("COMIC");
        assertThat(result.getImportStatus()).isEqualTo("PARSING");
        verify(sourceRepository).save(any(ReaderItemSource.class));
        verify(taskDispatchService).enqueue(any(), any(), any(), any());
        // 在途的文本解析任务必须一起作废：它跑完会按文本口径回写状态，把漫画条目覆写成 FAILED
        verify(taskRecordService).cancelActiveResourceTasks(
                eq(OWNER_ID),
                eq("READER_ITEM"),
                eq(List.of(EXISTING_ITEM_ID)),
                anyList(),
                eq("COMIC_PARSE")
        );
    }

    @Test
    void importExistingComicUpgradeWithSourceReparsesAsComic() {
        // 升级为漫画且该文件已是 source 时，应触发漫画重解析，而非提交文本解析
        ReaderItem existingItem = comicItem(EXISTING_ITEM_ID, OWNER_ID, FILE_NODE_ID, "画册");
        existingItem.setContentKind("TEXT");
        existingItem.setContentHash(sha256(FILE_BYTES));
        ReaderItemSource existingSource = new ReaderItemSource();
        existingSource.setId(UUID.fromString("60000000-0000-0000-0000-000000000001"));
        existingSource.setReaderItemId(EXISTING_ITEM_ID);
        existingSource.setFileNodeId(FILE_NODE_ID);
        existingSource.setStatus(ReaderSourceStatus.READY);

        when(itemRepository.findAccessibleByFileNodeId(OWNER_ID, FILE_NODE_ID, SpaceType.SHARED))
                .thenReturn(List.of(existingItem));
        when(itemRepository.findByIdForUpdate(EXISTING_ITEM_ID)).thenReturn(Optional.of(existingItem));
        when(fileMetadataQueryService.findById(FILE_NODE_ID))
                .thenReturn(Optional.of(personalFileNode("画册.epub")));
        when(fileDetector.detectType("画册.epub")).thenReturn("EPUB");
        when(itemRepository.save(existingItem)).thenReturn(existingItem);
        when(sourceRepository.findByReaderItemIdAndFileNodeId(EXISTING_ITEM_ID, FILE_NODE_ID))
                .thenReturn(Optional.of(existingSource));
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, EXISTING_ITEM_ID)).thenReturn(true);

        importService.importFile(OWNER_ID, FILE_NODE_ID, false, "COMIC");

        verify(comicManifestService).enqueueManifestReparse(EXISTING_ITEM_ID);
        verify(textParseSubmissionService, never()).submit(any(), anyBoolean());
    }

    @Test
    void importDetectsContentHashDuplicateInSameSpace() {
        // 共享空间内相同内容 → 复用已有条目
        ReaderItem dupItem = comicItem(EXISTING_ITEM_ID, OTHER_USER_ID, DUP_FILE_NODE_ID, "共享副本");
        FileDescriptor dupFileNode = sharedFileNode("shared.txt", OTHER_USER_ID);

        when(fileMetadataQueryService.findById(FILE_NODE_ID))
                .thenReturn(Optional.of(sharedFileNode("book.txt", OWNER_ID)));
        stubReadFileBytes();
        when(fileDetector.detectType("book.txt")).thenReturn("TXT");
        when(itemRepository.findByContentHash(sha256(FILE_BYTES))).thenReturn(List.of(dupItem));
        when(fileMetadataQueryService.findById(DUP_FILE_NODE_ID)).thenReturn(Optional.of(dupFileNode));
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, EXISTING_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID);

        assertThat(result.getId()).isEqualTo(EXISTING_ITEM_ID);
        verify(itemRepository, never()).save(any());
        verify(bookshelfRepository).save(any(ReaderBookshelf.class));
    }

    @Test
    void importDoesNotReuseSharedWorkForPrivateUpload() {
        // 私有上传不得静默复用他人创建的共享条目：两条内容的归属与清理边界不同
        ReaderItem dupItem = comicItem(EXISTING_ITEM_ID, OTHER_USER_ID, DUP_FILE_NODE_ID, "共享副本");
        ReaderItem savedItem = new ReaderItem();
        savedItem.setId(SAVED_ITEM_ID);

        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(personalFileNode("book.txt")));
        stubReadFileBytes();
        when(fileDetector.detectType("book.txt")).thenReturn("TXT");
        when(itemRepository.findByContentHash(sha256(FILE_BYTES))).thenReturn(List.of(dupItem));
        when(fileMetadataQueryService.findById(DUP_FILE_NODE_ID))
                .thenReturn(Optional.of(sharedFileNode(DUP_FILE_NODE_ID, "shared.txt", OTHER_USER_ID)));
        when(itemRepository.save(any(ReaderItem.class))).thenReturn(savedItem);
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, SAVED_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID);

        assertThat(result.getId()).isEqualTo(SAVED_ITEM_ID);
    }

    @Test
    void importForceCreatesIndependentCopy() {
        // 强制导入 → 跳过内容哈希去重，创建独立副本
        ReaderItem savedItem = new ReaderItem();
        savedItem.setId(SAVED_ITEM_ID);

        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(personalFileNode("book.txt")));
        stubReadFileBytes();
        when(fileDetector.detectType("book.txt")).thenReturn("TXT");
        when(itemRepository.save(any(ReaderItem.class))).thenReturn(savedItem);
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, SAVED_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID, true);

        assertThat(result.getId()).isEqualTo(SAVED_ITEM_ID);
        verify(itemRepository).save(any(ReaderItem.class));
        verify(itemRepository, never()).findByContentHash(any());
    }

    @Test
    void importComicPartMergesIntoExistingWork() {
        // 个人空间内文件名包含明确话数信号时，同一作品的分包应并入已有漫画条目
        ReaderItem existingItem = comicItem(EXISTING_ITEM_ID, OWNER_ID, DUP_FILE_NODE_ID, "银河轨道");

        when(fileMetadataQueryService.findById(FILE_NODE_ID))
                .thenReturn(Optional.of(personalFileNode("银河轨道 第001话.cbz")));
        stubReadFileBytes();
        when(fileDetector.detectType("银河轨道 第001话.cbz")).thenReturn("CBZ");
        when(fileDetector.detectContentKind("CBZ")).thenReturn("COMIC");
        when(itemRepository.findPersonalComicCandidates(OWNER_ID, SpaceType.PERSONAL, "COMIC"))
                .thenReturn(List.of(existingItem));
        when(itemRepository.findByIdForUpdate(EXISTING_ITEM_ID)).thenReturn(Optional.of(existingItem));
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, EXISTING_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(sourceRepository.findByReaderItemIdAndFileNodeId(EXISTING_ITEM_ID, FILE_NODE_ID))
                .thenReturn(Optional.empty());
        when(sourceRepository.save(any(ReaderItemSource.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(itemRepository.save(existingItem)).thenReturn(existingItem);

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID);

        assertThat(result.getId()).isEqualTo(EXISTING_ITEM_ID);
        ArgumentCaptor<ReaderItemSource> sourceCaptor = ArgumentCaptor.forClass(ReaderItemSource.class);
        verify(sourceRepository).save(sourceCaptor.capture());
        assertThat(sourceCaptor.getValue().getReaderItemId()).isEqualTo(EXISTING_ITEM_ID);
        assertThat(sourceCaptor.getValue().getStatus()).isEqualTo(ReaderSourceStatus.PENDING);
        verify(taskDispatchService).enqueue(any(), any(), any(), any());
    }

    @Test
    void importSharedComicPartMergesAnotherUsersWorkAndKeepsFileOwnerInTaskEvent() {
        // 场景 A：B 把第 2 卷传到共享空间，应并入 A 创建的共享作品，
        // 且解析事件必须带分卷上传者的用户 id，否则 Worker 的文件守卫会把合法分卷判成已删除。
        ReaderItem sharedWork = comicItem(EXISTING_ITEM_ID, OTHER_USER_ID, DUP_FILE_NODE_ID, "芙莉莲");
        UUID volumeSourceId = UUID.fromString("60000000-0000-0000-0000-000000000009");

        when(fileMetadataQueryService.findById(FILE_NODE_ID))
                .thenReturn(Optional.of(sharedFileNode("芙莉莲 第02卷.cbz", OWNER_ID)));
        stubReadFileBytes();
        when(fileDetector.detectType("芙莉莲 第02卷.cbz")).thenReturn("CBZ");
        when(fileDetector.detectContentKind("CBZ")).thenReturn("COMIC");
        when(itemRepository.findSharedComicCandidates(SpaceType.SHARED, "COMIC"))
                .thenReturn(List.of(sharedWork));
        when(itemRepository.findByIdForUpdate(EXISTING_ITEM_ID)).thenReturn(Optional.of(sharedWork));
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, EXISTING_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(sourceRepository.findByReaderItemIdAndFileNodeId(EXISTING_ITEM_ID, FILE_NODE_ID))
                .thenReturn(Optional.empty());
        when(sourceRepository.save(any(ReaderItemSource.class))).thenAnswer(invocation -> {
            ReaderItemSource source = invocation.getArgument(0);
            source.setId(volumeSourceId);
            return source;
        });
        when(itemRepository.save(sharedWork)).thenReturn(sharedWork);

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID);

        assertThat(result.getId()).isEqualTo(EXISTING_ITEM_ID);
        ArgumentCaptor<ComicParseTaskEvent> eventCaptor = ArgumentCaptor.forClass(ComicParseTaskEvent.class);
        verify(taskDispatchService).enqueue(any(), any(), any(), eventCaptor.capture());
        assertThat(eventCaptor.getValue().ownerUserId()).isEqualTo(OWNER_ID);
        assertThat(eventCaptor.getValue().itemId()).isEqualTo(EXISTING_ITEM_ID);
        ArgumentCaptor<UUID> taskOwnerCaptor = ArgumentCaptor.forClass(UUID.class);
        verify(taskRecordService).createQueuedTask(
                any(), taskOwnerCaptor.capture(), eq("COMIC_PARSE"), any(), any(), eq("FILE_NODE"),
                eq(FILE_NODE_ID), any());
        assertThat(taskOwnerCaptor.getValue()).isEqualTo(OTHER_USER_ID);
        verify(syncEventService).invalidate(eq(OTHER_USER_ID), eq(SyncScope.READER), eq("READER_LIBRARY"), any());
        verify(syncEventService).invalidate(eq(OWNER_ID), eq(SyncScope.READER), eq("READER_LIBRARY"), any());
    }

    @Test
    void importPersonalComicPartDoesNotMergeSharedWork() {
        // 场景 B：私有分卷只在个人空间候选里查找，绝不并入他人创建的共享作品
        ReaderItem savedItem = new ReaderItem();
        savedItem.setId(SAVED_ITEM_ID);

        when(fileMetadataQueryService.findById(FILE_NODE_ID))
                .thenReturn(Optional.of(personalFileNode("芙莉莲 第02卷.cbz")));
        stubReadFileBytes();
        when(fileDetector.detectType("芙莉莲 第02卷.cbz")).thenReturn("CBZ");
        when(fileDetector.detectContentKind("CBZ")).thenReturn("COMIC");
        when(itemRepository.findPersonalComicCandidates(OWNER_ID, SpaceType.PERSONAL, "COMIC"))
                .thenReturn(List.of());
        when(itemRepository.save(any(ReaderItem.class))).thenReturn(savedItem);
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, SAVED_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(sourceRepository.findByReaderItemIdAndFileNodeId(SAVED_ITEM_ID, FILE_NODE_ID))
                .thenReturn(Optional.empty());
        when(sourceRepository.save(any(ReaderItemSource.class))).thenAnswer(invocation -> invocation.getArgument(0));

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID);

        assertThat(result.getId()).isEqualTo(SAVED_ITEM_ID);
        verify(itemRepository, never()).findSharedComicCandidates(any(), any());
    }

    @Test
    void importComicWithoutPartSignalCreatesIndependentWork() {
        // 文件名没有话数、卷数或分包信号时，不应仅凭相同规范化标题自动并入已有漫画
        ReaderItem savedItem = new ReaderItem();
        savedItem.setId(SAVED_ITEM_ID);

        when(fileMetadataQueryService.findById(FILE_NODE_ID))
                .thenReturn(Optional.of(personalFileNode("银河轨道 2024.cbz")));
        stubReadFileBytes();
        when(fileDetector.detectType("银河轨道 2024.cbz")).thenReturn("CBZ");
        when(fileDetector.detectContentKind("CBZ")).thenReturn("COMIC");
        when(itemRepository.save(any(ReaderItem.class))).thenReturn(savedItem);
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, SAVED_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(sourceRepository.save(any(ReaderItemSource.class))).thenAnswer(invocation -> invocation.getArgument(0));

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID);

        assertThat(result.getId()).isEqualTo(SAVED_ITEM_ID);
        verify(itemRepository, never()).findPersonalComicCandidates(any(), any(), any());
        verify(sourceRepository).save(any(ReaderItemSource.class));
        verify(taskDispatchService).enqueue(any(), any(), any(), any());
    }

    @Test
    void importComicUsesNormalizedWorkTitle() {
        ReaderItem savedItem = new ReaderItem();
        savedItem.setId(SAVED_ITEM_ID);

        when(fileMetadataQueryService.findById(FILE_NODE_ID))
                .thenReturn(Optional.of(personalFileNode("[Kmoe][紹宋]話001-010.epub")));
        stubReadFileBytes();
        when(fileDetector.detectType("[Kmoe][紹宋]話001-010.epub")).thenReturn("EPUB");
        when(itemRepository.save(any(ReaderItem.class))).thenReturn(savedItem);
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, SAVED_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(sourceRepository.save(any(ReaderItemSource.class))).thenAnswer(invocation -> invocation.getArgument(0));

        importService.importFile(OWNER_ID, FILE_NODE_ID, false, "COMIC");

        ArgumentCaptor<ReaderItem> itemCaptor = ArgumentCaptor.forClass(ReaderItem.class);
        verify(itemRepository).save(itemCaptor.capture());
        assertThat(itemCaptor.getValue().getTitle()).isEqualTo("紹宋");
    }

    @Test
    void importEpubAsComicCreatesComicSource() {
        // EPUB 可由用户显式选择漫画引擎，不依赖 fixed-layout 预检测结果
        ReaderItem savedItem = new ReaderItem();
        savedItem.setId(SAVED_ITEM_ID);

        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(personalFileNode("画册.epub")));
        stubReadFileBytes();
        when(fileDetector.detectType("画册.epub")).thenReturn("EPUB");
        when(itemRepository.save(any(ReaderItem.class))).thenReturn(savedItem);
        when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, SAVED_ITEM_ID)).thenReturn(false);
        when(bookshelfRepository.save(any(ReaderBookshelf.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(sourceRepository.save(any(ReaderItemSource.class))).thenAnswer(invocation -> invocation.getArgument(0));

        ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID, false, "COMIC");

        assertThat(result.getId()).isEqualTo(SAVED_ITEM_ID);
        ArgumentCaptor<ReaderItem> itemCaptor = ArgumentCaptor.forClass(ReaderItem.class);
        verify(itemRepository).save(itemCaptor.capture());
        assertThat(itemCaptor.getValue().getContentKind()).isEqualTo("COMIC");
        assertThat(itemCaptor.getValue().getItemType()).isEqualTo("EPUB");
        verify(sourceRepository).save(any(ReaderItemSource.class));
        verify(taskDispatchService).enqueue(any(), any(), any(), any());
        verify(fileDetector, never()).detectContentKind("EPUB");
    }

    @Test
    void importTxtAsComicIsRejected() {
        // TXT 文件不能被强制导入为漫画，避免进入错误解析引擎
        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(personalFileNode("book.txt")));
        when(fileDetector.detectType("book.txt")).thenReturn("TXT");
        stubReadFileBytes();

        assertThatThrownBy(() -> importService.importFile(OWNER_ID, FILE_NODE_ID, false, "COMIC"))
                .isInstanceOf(BusinessException.class)
                .satisfies(ex -> assertThat(((BusinessException) ex).errorCode()).isEqualTo(ErrorCode.PARAM_ERROR));

        verify(itemRepository, never()).save(any());
    }

    @Test
    void importRejectsPersonalFileFromOtherUser() {
        // 个人空间文件不允许其他用户导入
        FileDescriptor otherUserFile = fileDescriptor(
                FILE_NODE_ID, OTHER_USER_ID, SpaceType.PERSONAL, "secret.txt", null);

        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(otherUserFile));

        assertThatThrownBy(() -> importService.importFile(OWNER_ID, FILE_NODE_ID))
                .isInstanceOf(BusinessException.class)
                .satisfies(ex -> assertThat(((BusinessException) ex).errorCode()).isEqualTo(ErrorCode.FORBIDDEN));
    }

    @Test
    void cancelImportStopsActiveTasksAndPersistsRetryableFailureState() {
        ReaderItem item = new ReaderItem();
        item.setId(SAVED_ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(FILE_NODE_ID);
        item.setImportStatus("PARSING");
        ReaderItemSource source = new ReaderItemSource();
        source.setReaderItemId(SAVED_ITEM_ID);
        source.setFileNodeId(FILE_NODE_ID);
        source.setStatus(ReaderSourceStatus.PARSING);
        when(itemRepository.findByIdAndOwnerUserId(SAVED_ITEM_ID, OWNER_ID)).thenReturn(Optional.of(item));
        when(sourceRepository.findByReaderItemId(SAVED_ITEM_ID)).thenReturn(List.of(source));
        when(sourceRepository.saveAll(any())).thenAnswer(invocation -> invocation.getArgument(0));
        when(itemRepository.save(item)).thenReturn(item);

        importService.cancelImport(OWNER_ID, SAVED_ITEM_ID);

        assertThat(item.getImportStatus()).isEqualTo("FAILED");
        assertThat(item.getParseErrorCode()).isEqualTo("IMPORT_CANCELLED");
        assertThat(source.getStatus()).isEqualTo(ReaderSourceStatus.FAILED);
        assertThat(source.getErrorCode()).isEqualTo("IMPORT_CANCELLED");
        verify(taskRecordService).cancelActiveResourceTasks(
                eq(OWNER_ID), eq("FILE_NODE"), eq(List.of(FILE_NODE_ID)), any(), eq("FILE_PURGE"));
        verify(taskRecordService).cancelActiveResourceTasks(
                eq(OWNER_ID), eq("READER_ITEM"), eq(List.of(SAVED_ITEM_ID)), any(), eq("FILE_PURGE"));
        verify(syncEventService).invalidate(eq(OWNER_ID), any(), eq("READER_LIBRARY"), any());
    }

    @Test
    void importPdfDefersCoverStoreUntilTheTransactionCommits() {
        // 封面服务开的是 REQUIRES_NEW 独立事务：首次导入时条目还没提交，
        // 同步保存封面会查不到行并抛 BOOK_NOT_FOUND，把整次导入一起回滚。
        ReaderItem savedItem = new ReaderItem();
        savedItem.setId(SAVED_ITEM_ID);
        TransactionSynchronizationManager.initSynchronization();
        try {
            when(fileMetadataQueryService.findById(FILE_NODE_ID))
                    .thenReturn(Optional.of(personalFileNode("报告.pdf")));
            stubReadFileBytes();
            when(fileDetector.detectType("报告.pdf")).thenReturn("PDF");
            when(itemRepository.save(any(ReaderItem.class))).thenReturn(savedItem);
            when(bookshelfRepository.existsByOwnerUserIdAndReaderItemId(OWNER_ID, SAVED_ITEM_ID)).thenReturn(false);
            when(bookshelfRepository.save(any(ReaderBookshelf.class)))
                    .thenAnswer(invocation -> invocation.getArgument(0));
            when(pdfMetadataService.extract(any(FileDescriptor.class)))
                    .thenReturn(new ReaderPdfMetadataService.PdfMetadata(12, new byte[] {1, 2, 3}));
            when(sourceRepository.save(any(ReaderItemSource.class)))
                    .thenAnswer(invocation -> invocation.getArgument(0));

            ReaderItem result = importService.importFile(OWNER_ID, FILE_NODE_ID);

            assertThat(result.getImportStatus()).isEqualTo("READY");
            verify(coverExtractionService, never()).store(any(), any(), anyBoolean());

            TransactionSynchronizationManager.getSynchronizations()
                    .forEach(synchronization -> synchronization.afterCommit());

            verify(coverExtractionService).store(eq(SAVED_ITEM_ID), any(), eq(false));
        } finally {
            TransactionSynchronizationManager.clearSynchronization();
        }
    }

    @Test
    void reparsePdfItemKeepsTheItemReadyAndNeverSubmitsTextParse() {
        // PDF 由客户端渲染，重新解析只补页数与封面；投给文本解析引擎会把可读条目写成 FAILED
        ReaderItem item = new ReaderItem();
        item.setId(SAVED_ITEM_ID);
        item.setOwnerUserId(OWNER_ID);
        item.setFileNodeId(FILE_NODE_ID);
        item.setItemType("PDF");
        item.setContentKind("TEXT");
        item.setImportStatus("READY");
        ReaderItemSource existingSource = new ReaderItemSource();
        existingSource.setReaderItemId(SAVED_ITEM_ID);
        existingSource.setFileNodeId(FILE_NODE_ID);
        existingSource.setStatus(ReaderSourceStatus.READY);

        when(fileMetadataQueryService.findById(FILE_NODE_ID))
                .thenReturn(Optional.of(personalFileNode("报告.pdf")));
        when(itemRepository.save(item)).thenReturn(item);
        when(pdfMetadataService.extract(any(FileDescriptor.class)))
                .thenReturn(new ReaderPdfMetadataService.PdfMetadata(30, null));
        when(sourceRepository.findByReaderItemIdAndFileNodeId(SAVED_ITEM_ID, FILE_NODE_ID))
                .thenReturn(Optional.of(existingSource));

        importService.reparsePdfItem(OWNER_ID, item);

        assertThat(item.getImportStatus()).isEqualTo("READY");
        assertThat(existingSource.getPageCount()).isEqualTo(30);
        verify(textParseSubmissionService, never()).submit(any(), anyBoolean());
        verify(sourceRepository).save(existingSource);
    }

    // ==================== 辅助方法 ====================

    /** 创建漫画条目夹具。 */
    private ReaderItem comicItem(UUID itemId, UUID ownerUserId, UUID fileNodeId, String title) {
        ReaderItem item = new ReaderItem();
        item.setId(itemId);
        item.setOwnerUserId(ownerUserId);
        item.setFileNodeId(fileNodeId);
        item.setTitle(title);
        item.setContentKind("COMIC");
        item.setItemType("CBZ");
        return item;
    }

    /** 创建个人空间文件节点。 */
    private FileDescriptor personalFileNode(String name) {
        return fileDescriptor(FILE_NODE_ID, OWNER_ID, SpaceType.PERSONAL, name, FILE_OBJECT_ID);
    }

    /** 创建共享空间文件节点。 */
    private FileDescriptor sharedFileNode(String name, UUID uploaderId) {
        return sharedFileNode(FILE_NODE_ID, name, uploaderId);
    }

    /** 创建指定节点 id 的共享空间文件节点。 */
    private FileDescriptor sharedFileNode(UUID id, String name, UUID uploaderId) {
        return new FileDescriptor(
                id,
                uploaderId,
                null,
                "FILE",
                name,
                "/" + name,
                "application/octet-stream",
                FILE_BYTES.length,
                FILE_OBJECT_ID,
                "UPLOAD",
                false,
                true,
                SpaceType.SHARED,
                uploaderId,
                null,
                null
        );
    }

    /** 创建文件节点描述符。 */
    private FileDescriptor fileDescriptor(
            UUID id,
            UUID ownerUserId,
            SpaceType spaceType,
            String name,
            UUID currentObjectId) {
        return new FileDescriptor(
                id,
                ownerUserId,
                null,
                "FILE",
                name,
                "/" + name,
                "application/octet-stream",
                FILE_BYTES.length,
                currentObjectId,
                "UPLOAD",
                false,
                false,
                spaceType,
                ownerUserId,
                null,
                null
        );
    }

    /** 桩：读取文件字节的完整调用链。 */
    private void stubReadFileBytes() {
        when(fileQueryService.openOwnedFileContent(any(), any()))
                .thenAnswer(invocation -> new FileContentStream(
                        new ByteArrayInputStream(FILE_BYTES),
                        "book.txt",
                        FILE_BYTES.length,
                        "application/octet-stream"
                ));
    }

    /** 计算字节数组的 SHA-256 哈希（十六进制小写）。 */
    private String sha256(byte[] data) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(data);
            StringBuilder hex = new StringBuilder(64);
            for (byte b : hash) {
                hex.append(String.format("%02x", b));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException ex) {
            throw new RuntimeException(ex);
        }
    }
}
