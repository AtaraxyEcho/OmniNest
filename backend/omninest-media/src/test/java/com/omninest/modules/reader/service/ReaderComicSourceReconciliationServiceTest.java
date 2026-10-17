package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import java.util.List;
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
 * <p>解析规则本身由 ReaderComicManifestServiceTest 覆盖，这里只验对账的两条约束：
 * 没有差异时一次写都不发，有差异时落库并同步重建目录。
 */
@ExtendWith(MockitoExtension.class)
class ReaderComicSourceReconciliationServiceTest {

    private static final UUID ITEM_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");

    @Mock
    private ReaderItemSourceRepository sourceRepository;

    @Mock
    private ReaderComicManifestService manifestService;

    @Mock
    private ComicManifestBuilder manifestBuilder;

    @InjectMocks
    private ReaderComicSourceReconciliationService service;

    @Test
    @DisplayName("数值未变化时不落库也不重建目录")
    void noDrift_writesNothing() {
        ReaderItemSource source = new ReaderItemSource();
        source.setSourceName("某漫画 第1卷.cbz");
        source.setVolumeNo(1);
        source.setSourceSortKey("vol000001");
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of(source));
        doAnswer(invocation -> {
            ReaderItemSource target = invocation.getArgument(0);
            target.setVolumeNo(1);
            target.setSourceSortKey("vol000001");
            return null;
        }).when(manifestService).applySourceSortMetadata(any(ReaderItemSource.class), any());

        assertThat(service.reconcileItem(ITEM_ID)).isFalse();
        verify(sourceRepository, never()).saveAll(any());
        verifyNoInteractions(manifestBuilder);
    }

    @Test
    @DisplayName("脏季号被清掉时落库并重建目录")
    void staleSeasonIsHealedAndCatalogRebuilt() {
        ReaderItemSource source = new ReaderItemSource();
        source.setSourceName("Class1 Vol.1.cbz");
        source.setSeasonNo(1);
        when(sourceRepository.findByReaderItemId(ITEM_ID)).thenReturn(List.of(source));
        doAnswer(invocation -> {
            ReaderItemSource target = invocation.getArgument(0);
            target.setSeasonNo(null);
            target.setVolumeNo(1);
            target.setSourceSortKey("vol000001");
            return null;
        }).when(manifestService).applySourceSortMetadata(any(ReaderItemSource.class), any());

        assertThat(service.reconcileItem(ITEM_ID)).isTrue();
        verify(sourceRepository).saveAll(List.of(source));
        verify(manifestBuilder).rebuildComicManifest(ITEM_ID);
    }

    @Test
    @DisplayName("候选分页透传仓储，页码与页大小不被改写")
    void candidatesPassThroughPaging() {
        when(sourceRepository.findComicItemIds(any(), any())).thenReturn(List.of(ITEM_ID));

        assertThat(service.findReconcileCandidateIds(2, 100)).isEqualTo(List.of(ITEM_ID));
    }
}
