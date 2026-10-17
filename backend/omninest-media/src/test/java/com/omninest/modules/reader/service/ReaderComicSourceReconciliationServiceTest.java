package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderPage;
import com.omninest.modules.reader.repository.ReaderItemRepository;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.reader.repository.ReaderPageRepository;
import com.omninest.modules.reader.service.ReaderComicSourceReconciliationService.ReconcileOutcome;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 漫画来源排序元数据对账服务单元测试。
 *
 * <p>解析规则本身由 ReaderComicManifestServiceTest 覆盖，这里验对账的三条约束：无差异时
 * 一次写都不发；只有目录形状真变化才重建清单；试运行在任何情况下都不落库。
 */
@ExtendWith(MockitoExtension.class)
class ReaderComicSourceReconciliationServiceTest {

    private static final UUID ITEM_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID SOURCE_ID = UUID.fromString("40000000-0000-0000-0000-000000000001");
    private static final UUID GHOST_SOURCE_ID = UUID.fromString("40000000-0000-0000-0000-000000000002");
    private static final UUID NODE_ID = UUID.fromString("50000000-0000-0000-0000-000000000001");

    @Mock
    private ReaderItemRepository itemRepository;

    @Mock
    private ReaderItemSourceRepository sourceRepository;

    @Mock
    private ReaderPageRepository pageRepository;

    @Mock
    private ReaderComicManifestService manifestService;

    @Mock
    private ComicManifestBuilder manifestBuilder;

    @InjectMocks
    private ReaderComicSourceReconciliationService service;

    @Test
    @DisplayName("数值未变化时不落库也不重建目录")
    void noDrift_writesNothing() {
        ReaderItemSource source = source("葬送的芙莉莲 第一卷.cbz");
        source.setVolumeNo(1);
        when(itemRepository.findByIdForUpdate(ITEM_ID)).thenReturn(Optional.of(item()));
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of(source));
        doAnswer(invocation -> {
            ReaderItemSource target = invocation.getArgument(0);
            target.setVolumeNo(1);
            return null;
        }).when(manifestService).applySourceSortMetadata(any(ReaderItemSource.class), any());

        assertThat(service.reconcileItem(ITEM_ID)).isEqualTo(ReconcileOutcome.UNCHANGED);
        verify(sourceRepository, never()).saveAll(any());
        verifyNoInteractions(manifestBuilder);
    }

    @Test
    @DisplayName("条目不存在时直接结束，不读来源")
    void missingItem_skipsBeforeRead() {
        when(itemRepository.findByIdForUpdate(ITEM_ID)).thenReturn(Optional.empty());

        assertThat(service.reconcileItem(ITEM_ID)).isEqualTo(ReconcileOutcome.UNCHANGED);
        verifyNoInteractions(sourceRepository);
    }

    @Test
    @DisplayName("目录形状变化时落库、清悬空引用并重建清单")
    void shapeChange_healsAndRebuilds() {
        ReaderItemSource source = source("Class1 Vol.1.cbz");
        // 过去无边界正则把 "Class1" 认成第 1 季留下的脏值。
        source.setSeasonNo(1);
        when(itemRepository.findByIdForUpdate(ITEM_ID)).thenReturn(Optional.of(item()));
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of(source));
        doAnswer(invocation -> {
            ReaderItemSource target = invocation.getArgument(0);
            target.setSeasonNo(null);
            target.setVolumeNo(1);
            return null;
        }).when(manifestService).applySourceSortMetadata(any(ReaderItemSource.class), any());
        ReaderPage ghostPage = page(GHOST_SOURCE_ID);
        ReaderPage livePage = page(SOURCE_ID);
        when(pageRepository.findByReaderItemIdOrderByPageIndex(ITEM_ID))
                .thenReturn(List.of(ghostPage, livePage));

        assertThat(service.reconcileItem(ITEM_ID)).isEqualTo(ReconcileOutcome.REBUILD_REQUIRED);
        verify(sourceRepository).saveAll(List.of(source));
        assertThat(ghostPage.getCatalogNodeId()).isNull();
        assertThat(livePage.getCatalogNodeId()).isEqualTo(NODE_ID);
        verify(pageRepository).saveAll(List.of(ghostPage));
        verify(manifestBuilder).rebuildComicManifest(ITEM_ID);
    }

    @Test
    @DisplayName("只有排序键尾数漂移时改列不重建，客户端锚点不退化")
    void sortKeyOnlyDrift_updatesColumnsWithoutRebuild() {
        ReaderItemSource source = source("笔记 2.0.cbz");
        source.setSourceSortKey("笔记 2");
        when(itemRepository.findByIdForUpdate(ITEM_ID)).thenReturn(Optional.of(item()));
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of(source));
        doAnswer(invocation -> {
            ReaderItemSource target = invocation.getArgument(0);
            target.setSourceSortKey("笔记 2.0");
            return null;
        }).when(manifestService).applySourceSortMetadata(any(ReaderItemSource.class), any());

        assertThat(service.reconcileItem(ITEM_ID)).isEqualTo(ReconcileOutcome.METADATA_ONLY);
        verify(sourceRepository).saveAll(List.of(source));
        verifyNoInteractions(manifestBuilder);
        verify(pageRepository, never()).findByReaderItemIdOrderByPageIndex(any());
    }

    @Test
    @DisplayName("试运行有差异也不落库")
    void preview_neverWrites() {
        ReaderItemSource source = source("Class1 Vol.1.cbz");
        source.setSeasonNo(1);
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of(source));
        doAnswer(invocation -> {
            ReaderItemSource target = invocation.getArgument(0);
            target.setSeasonNo(null);
            target.setVolumeNo(1);
            return null;
        }).when(manifestService).applySourceSortMetadata(any(ReaderItemSource.class), any());

        assertThat(service.previewItem(ITEM_ID)).isEqualTo(ReconcileOutcome.REBUILD_REQUIRED);
        verify(sourceRepository, never()).saveAll(any());
        verifyNoInteractions(itemRepository, manifestBuilder);
    }

    private ReaderItem item() {
        ReaderItem item = new ReaderItem();
        item.setId(ITEM_ID);
        return item;
    }

    private ReaderItemSource source(String sourceName) {
        ReaderItemSource source = new ReaderItemSource();
        source.setId(SOURCE_ID);
        source.setReaderItemId(ITEM_ID);
        source.setSourceName(sourceName);
        return source;
    }

    private ReaderPage page(UUID sourceId) {
        ReaderPage page = new ReaderPage();
        page.setReaderItemId(ITEM_ID);
        page.setSourceId(sourceId);
        page.setCatalogNodeId(NODE_ID);
        return page;
    }
}
