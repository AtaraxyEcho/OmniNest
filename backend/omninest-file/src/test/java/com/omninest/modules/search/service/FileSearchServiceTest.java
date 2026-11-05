package com.omninest.modules.search.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.common.access.SharedSpaceAccessQuery;
import com.omninest.modules.search.dto.SearchResultDto;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 文件搜索数据库复核测试。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class FileSearchServiceTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ACTIVE_FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID STALE_FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000002");

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

    @Test
    void filtersStaleCandidatesAndUsesCurrentDatabaseTitle() {
        when(fileSearchIndexService.search(eq(USER_ID), eq("报告"), anyInt(), any())).thenReturn(List.of(
                new SearchResultDto(STALE_FILE_ID, "已删除标题", null, 2.0),
                new SearchResultDto(ACTIVE_FILE_ID, "旧标题", null, 1.0)
        ));
        when(searchableFileQuery.findCurrentNames(eq(USER_ID), any()))
                .thenReturn(Map.of(ACTIVE_FILE_ID, "数据库最新标题"));

        List<SearchResultDto> results = service.search(USER_ID, " 报告 ");

        assertThat(results).hasSize(1);
        assertThat(results.get(0).fileId()).isEqualTo(ACTIVE_FILE_ID);
        assertThat(results.get(0).title()).isEqualTo("数据库最新标题");
        verify(fileSearchIndexService).search(USER_ID, "报告", 150, "PERSONAL");
    }

    @Test
    void returnsDatabaseTitleMatchWhenLuceneHasNoCandidates() {
        when(fileSearchIndexService.search(eq(USER_ID), eq("新名字"), anyInt(), any()))
                .thenReturn(List.of());
        when(searchableFileQuery.searchActiveFilesByName(USER_ID, "新名字", true, false, 50))
                .thenReturn(Map.of(ACTIVE_FILE_ID, "新名字.pdf"));

        List<SearchResultDto> results = service.search(USER_ID, "新名字");

        assertThat(results).hasSize(1);
        assertThat(results.getFirst().fileId()).isEqualTo(ACTIVE_FILE_ID);
        assertThat(results.getFirst().title()).isEqualTo("新名字.pdf");
        assertThat(results.getFirst().snippet()).isNull();
    }

    @Test
    void appendsDatabaseTitleMatchAfterLuceneCandidates() {
        UUID otherId = UUID.fromString("20000000-0000-0000-0000-000000000003");
        when(fileSearchIndexService.search(eq(USER_ID), eq("报告"), anyInt(), any()))
                .thenReturn(List.of(new SearchResultDto(ACTIVE_FILE_ID, "旧标题", "正文", 2.0)));
        when(searchableFileQuery.findCurrentNames(eq(USER_ID), any()))
                .thenReturn(Map.of(ACTIVE_FILE_ID, "报告.pdf"));
        when(searchableFileQuery.searchActiveFilesByName(USER_ID, "报告", true, false, 50))
                .thenReturn(Map.of(otherId, "报告备份.pdf"));

        List<SearchResultDto> results = service.search(USER_ID, "报告");

        assertThat(results).extracting(SearchResultDto::fileId)
                .containsExactly(ACTIVE_FILE_ID, otherId);
        assertThat(results.get(0).snippet()).isEqualTo("正文");
        assertThat(results.get(1).snippet()).isNull();
    }

    @Test
    void blankQueryDoesNotAccessIndexOrDatabase() {
        assertThat(service.search(USER_ID, "  ")).isEmpty();
    }
}
