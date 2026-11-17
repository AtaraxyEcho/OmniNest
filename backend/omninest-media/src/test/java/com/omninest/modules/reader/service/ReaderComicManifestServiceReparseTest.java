package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.media.service.MediaSyncEventService;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderSourceStatus;
import com.omninest.modules.reader.repository.ReaderCatalogNodeRepository;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Consumer;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 漫画来源重解析的单测：锁定"归档落盘在事务外"和"解析失败不替换旧页面"两条性质。
 *
 * <p>这两条性质在事务边界上：单看结果码永远成立，只有记录落盘时的事务深度才区分得出来。
 * 用深度计数器模拟事务回调的执行区间，任何把 {@code stage} 挪回事务内的改动都会失败。</p>
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderComicManifestServiceReparseTest {

    private static final UUID OWNER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ITEM_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID FILE_NODE_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final long ARCHIVE_BYTES = 4096L;

    @Mock
    private ReaderItemRepository itemRepository;
    @Mock
    private ReaderItemSourceRepository sourceRepository;
    @Mock
    private ReaderCatalogNodeRepository catalogRepository;
    @Mock
    private ReaderPageRepository pageRepository;
    @Mock
    private FileMetadataQueryService fileMetadataQueryService;
    @Mock
    private ReaderComicArchiveParser archiveParser;
    @Mock
    private ComicManifestBuilder manifestBuilder;
    @Mock
    private ComicPageAssetService pageAssetService;
    @Mock
    private ReaderArchiveSafetyPolicy archiveSafetyPolicy;
    @Mock
    private ReaderEpubArchiveStager epubArchiveStager;
    @Mock
    private TaskDispatchService taskDispatchService;
    @Mock
    private TaskRecordService taskRecordService;
    @Mock
    private MediaSyncEventService syncEventService;
    @Mock
    private ReaderCoverExtractionService coverExtractionService;
    @Mock
    private TransactionTemplate transactionTemplate;

    @InjectMocks
    private ReaderComicManifestService service;

    @Test
    @DisplayName("归档落盘发生在事务回调之外，页面替换与清单重建在短事务内")
    void stagesArchiveOutsideTransactionAndReplacesPagesInsideOne() {
        AtomicInteger transactionDepth = new AtomicInteger();
        stubTransactionTemplate(transactionDepth);
        ReaderItemSource source = parsingSource();
        stubParserContext(source);

        AtomicInteger stageDepth = new AtomicInteger(-1);
        when(epubArchiveStager.stage(any(FileDescriptor.class))).thenAnswer(invocation -> {
            stageDepth.set(transactionDepth.get());
            return mock(ReaderEpubArchiveStager.StagedArchive.class);
        });
        when(archiveParser.parseEntries(any(), eq(ARCHIVE_BYTES), anyString()))
                .thenReturn(List.of(
                        new ReaderComicArchiveParser.ImageEntry("001.jpg", 100L, 0, 800, 1200),
                        new ReaderComicArchiveParser.ImageEntry("002.jpg", 120L, 1, 800, 1200)));

        List<Integer> progress = new ArrayList<>();
        service.parseExistingSource(ITEM_ID, SOURCE_ID, progress::add);

        assertThat(stageDepth.get())
                .as("整包落盘必须发生在两个短事务之间，否则会长时间占用数据库连接")
                .isZero();
        assertThat(progress).containsExactly(20, 30, 70, 90, 95);
        assertThat(source.getStatus()).isEqualTo(ReaderSourceStatus.READY);
        assertThat(source.getPageCount()).isEqualTo(2);
        verify(pageRepository).deleteBySourceId(SOURCE_ID);
        verify(pageRepository).saveAll(any());
        verify(manifestBuilder).rebuildComicManifest(ITEM_ID);
    }

    @Test
    @DisplayName("解析失败时保留旧页面与旧清单，异常向上抛给任务层标失败")
    void keepsPreviousPagesWhenArchiveParsingFails() {
        stubTransactionTemplate(new AtomicInteger());
        ReaderItemSource source = parsingSource();
        stubParserContext(source);
        when(epubArchiveStager.stage(any(FileDescriptor.class)))
                .thenReturn(mock(ReaderEpubArchiveStager.StagedArchive.class));
        when(archiveParser.parseEntries(any(), anyLong(), anyString()))
                .thenThrow(new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "压缩包已损坏"));

        assertThatThrownBy(() -> service.parseExistingSource(ITEM_ID, SOURCE_ID, ignored -> {
        }))
                .isInstanceOf(BusinessException.class)
                .hasMessage("压缩包已损坏");

        verify(pageRepository, never()).deleteBySourceId(any());
        verify(pageRepository, never()).saveAll(any());
        verify(manifestBuilder, never()).rebuildComicManifest(any());
        assertThat(source.getStatus()).isEqualTo(ReaderSourceStatus.PARSING);
        assertThat(source.getPageCount()).isZero();
    }

    @Test
    @DisplayName("已 READY 的来源直接返回，不重复落盘与解析")
    void skipsReadySourceWithoutStaging() {
        when(transactionTemplate.execute(any())).thenAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            return callback.doInTransaction(null);
        });
        ReaderItemSource source = parsingSource();
        source.setStatus(ReaderSourceStatus.READY);
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        stubItemStatusLookup();

        service.parseExistingSource(ITEM_ID, SOURCE_ID, ignored -> {
        });

        verify(epubArchiveStager, never()).stage(any());
        verify(pageRepository, never()).deleteBySourceId(any());
        verify(sourceRepository, never()).save(source);
    }

    private void stubTransactionTemplate(AtomicInteger depth) {
        doAnswer(invocation -> {
            TransactionCallback<?> callback = invocation.getArgument(0);
            depth.incrementAndGet();
            try {
                return callback.doInTransaction(null);
            } finally {
                depth.decrementAndGet();
            }
        }).when(transactionTemplate).execute(any());
        doAnswer(invocation -> {
            Consumer<TransactionStatus> action = invocation.getArgument(0);
            depth.incrementAndGet();
            try {
                action.accept(null);
            } finally {
                depth.decrementAndGet();
            }
            return null;
        }).when(transactionTemplate).executeWithoutResult(any());
    }

    private void stubParserContext(ReaderItemSource source) {
        when(sourceRepository.findById(SOURCE_ID)).thenReturn(Optional.of(source));
        when(fileMetadataQueryService.findById(FILE_NODE_ID)).thenReturn(Optional.of(fileNode()));
        when(pageAssetService.findPageAssets(SOURCE_ID)).thenReturn(List.of());
        when(sourceRepository.save(any(ReaderItemSource.class))).thenAnswer(invocation -> invocation.getArgument(0));
        stubItemStatusLookup();
    }

    private void stubItemStatusLookup() {
        when(itemRepository.findById(ITEM_ID)).thenReturn(Optional.empty());
    }

    private ReaderItemSource parsingSource() {
        ReaderItemSource source = new ReaderItemSource();
        source.setId(SOURCE_ID);
        source.setReaderItemId(ITEM_ID);
        source.setFileNodeId(FILE_NODE_ID);
        source.setFileFormat("CBZ");
        source.setSourceName("作品 第001话.cbz");
        source.setStatus(ReaderSourceStatus.PARSING);
        return source;
    }

    private FileDescriptor fileNode() {
        return new FileDescriptor(
                FILE_NODE_ID,
                OWNER_ID,
                null,
                "FILE",
                "作品 第001话.cbz",
                "/作品 第001话.cbz",
                "application/vnd.comicbook+zip",
                ARCHIVE_BYTES,
                null,
                "UPLOAD",
                false,
                false,
                SpaceType.PERSONAL,
                OWNER_ID,
                null,
                null
        );
    }
}
