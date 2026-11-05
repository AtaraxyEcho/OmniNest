package com.omninest.modules.search.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.access.SharedSpaceAccessQuery;
import com.omninest.modules.search.dto.SearchResultDto;
import com.omninest.modules.search.service.SearchableFileQuery.SearchableFileNode;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 文件搜索数据库复核测试。
 *
 * <p>正文索引只给出命中的内容对象，节点标识、文件名与可见性都由数据库解析。</p>
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class FileSearchServiceTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ACTIVE_FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID COPY_FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000009");
    private static final UUID ACTIVE_OBJECT_ID = UUID.fromString("30000000-0000-0000-0000-000000000001");
    private static final UUID STALE_OBJECT_ID = UUID.fromString("30000000-0000-0000-0000-000000000002");

    @Mock
    private FileSearchIndexService fileSearchIndexService;

    @Mock
    private SearchableFileQuery searchableFileQuery;

    @Mock
    private SharedSpaceAccessQuery sharedSpaceAccessQuery;

    private FileSearchService service;

    @BeforeEach
    void setUp() {
        lenient().when(sharedSpaceAccessQuery.canBrowse(USER_ID)).thenReturn(false);
        service = new FileSearchService(
                fileSearchIndexService, searchableFileQuery, sharedSpaceAccessQuery);
    }

    private void stubEmptyTitleMatches(String query) {
        lenient().when(searchableFileQuery.searchActiveFilesByName(USER_ID, query, true, false, 50))
                .thenReturn(Map.of());
    }

    @Test
    void resolvesObjectHitsToCurrentNodesAndDropsStaleOnes() {
        stubEmptyTitleMatches("报告");
        when(fileSearchIndexService.search(eq(USER_ID), eq("报告"), anyInt(), any())).thenReturn(List.of(
                new FileSearchIndexService.FileContentHit(STALE_OBJECT_ID, "已删除文件正文", 2.0F),
                new FileSearchIndexService.FileContentHit(ACTIVE_OBJECT_ID, "命中正文", 1.0F)
        ));
        when(searchableFileQuery.findSearchableNodesByObjectIds(eq(USER_ID), any(), eq(true), eq(false)))
                .thenReturn(List.of(new SearchableFileNode(ACTIVE_FILE_ID, ACTIVE_OBJECT_ID, "报告.pdf")));

        List<SearchResultDto> results = service.search(USER_ID, " 报告 ");

        assertThat(results).hasSize(1);
        assertThat(results.getFirst().fileId()).isEqualTo(ACTIVE_FILE_ID);
        assertThat(results.getFirst().title()).isEqualTo("报告.pdf");
        assertThat(results.getFirst().snippet()).isEqualTo("命中正文");
        verify(fileSearchIndexService).search(USER_ID, "报告", 150, "PERSONAL");
    }

    @Test
    @DisplayName("同一内容对象的多个副本都是独立命中结果")
    void everyCopyOfTheSameObjectBecomesItsOwnResult() {
        stubEmptyTitleMatches("合同");
        when(fileSearchIndexService.search(eq(USER_ID), eq("合同"), anyInt(), any()))
                .thenReturn(List.of(
                        new FileSearchIndexService.FileContentHit(ACTIVE_OBJECT_ID, "合同正文", 5.0F)));
        when(searchableFileQuery.findSearchableNodesByObjectIds(eq(USER_ID), any(), eq(true), eq(false)))
                .thenReturn(List.of(
                        new SearchableFileNode(ACTIVE_FILE_ID, ACTIVE_OBJECT_ID, "合同.pdf"),
                        new SearchableFileNode(COPY_FILE_ID, ACTIVE_OBJECT_ID, "合同 (1).pdf")));

        List<SearchResultDto> results = service.search(USER_ID, "合同");

        assertThat(results).extracting(SearchResultDto::fileId)
                .containsExactly(ACTIVE_FILE_ID, COPY_FILE_ID);
        assertThat(results).extracting(SearchResultDto::title)
                .containsExactly("合同.pdf", "合同 (1).pdf");
    }

    @Test
    void returnsDatabaseTitleMatchWhenLuceneHasNoCandidates() {
        when(fileSearchIndexService.search(eq(USER_ID), eq("新名字"), anyInt(), any())).thenReturn(List.of());
        when(searchableFileQuery.searchActiveFilesByName(USER_ID, "新名字", true, false, 50))
                .thenReturn(Map.of(ACTIVE_FILE_ID, "新名字.pdf"));

        List<SearchResultDto> results = service.search(USER_ID, "新名字");

        assertThat(results).hasSize(1);
        assertThat(results.getFirst().fileId()).isEqualTo(ACTIVE_FILE_ID);
        assertThat(results.getFirst().title()).isEqualTo("新名字.pdf");
        assertThat(results.getFirst().snippet()).isNull();
    }

    @Test
    void appendsDatabaseTitleMatchAfterContentCandidates() {
        UUID otherId = UUID.fromString("20000000-0000-0000-0000-000000000003");
        when(fileSearchIndexService.search(eq(USER_ID), eq("报告"), anyInt(), any()))
                .thenReturn(List.of(
                        new FileSearchIndexService.FileContentHit(ACTIVE_OBJECT_ID, "正文", 2.0F)));
        when(searchableFileQuery.findSearchableNodesByObjectIds(eq(USER_ID), any(), eq(true), eq(false)))
                .thenReturn(List.of(new SearchableFileNode(ACTIVE_FILE_ID, ACTIVE_OBJECT_ID, "报告.pdf")));
        when(searchableFileQuery.searchActiveFilesByName(USER_ID, "报告", true, false, 50))
                .thenReturn(Map.of(otherId, "报告备份.pdf"));

        List<SearchResultDto> results = service.search(USER_ID, "报告");

        assertThat(results).extracting(SearchResultDto::fileId)
                .containsExactly(ACTIVE_FILE_ID, otherId);
        assertThat(results.get(0).snippet()).isEqualTo("正文");
        assertThat(results.get(1).snippet()).isNull();
    }

    @Test
    void doesNotDuplicateANodeThatMatchesBothPaths() {
        when(fileSearchIndexService.search(eq(USER_ID), eq("报告"), anyInt(), any()))
                .thenReturn(List.of(
                        new FileSearchIndexService.FileContentHit(ACTIVE_OBJECT_ID, "正文", 2.0F)));
        when(searchableFileQuery.findSearchableNodesByObjectIds(eq(USER_ID), any(), eq(true), eq(false)))
                .thenReturn(List.of(new SearchableFileNode(ACTIVE_FILE_ID, ACTIVE_OBJECT_ID, "报告.pdf")));
        when(searchableFileQuery.searchActiveFilesByName(USER_ID, "报告", true, false, 50))
                .thenReturn(Map.of(ACTIVE_FILE_ID, "报告.pdf"));

        List<SearchResultDto> results = service.search(USER_ID, "报告");

        assertThat(results).extracting(SearchResultDto::fileId).containsExactly(ACTIVE_FILE_ID);
        assertThat(results.getFirst().snippet()).isEqualTo("正文");
    }

    @Test
    void blankQueryDoesNotAccessIndexOrDatabase() {
        assertThat(service.search(USER_ID, "  ")).isEmpty();
    }
}
