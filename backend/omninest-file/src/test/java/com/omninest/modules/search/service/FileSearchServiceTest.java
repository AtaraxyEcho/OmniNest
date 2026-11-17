package com.omninest.modules.search.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.omninest.common.access.SharedSpaceAccessQuery;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.search.dto.SearchResultDto;
import java.util.LinkedHashMap;
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
 * 文件搜索数据库文件名匹配测试。
 *
 * <p>正文索引已下线，文件名与可见性全部由数据库实时决定。</p>
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class FileSearchServiceTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");
    private static final UUID ACTIVE_FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000001");
    private static final UUID COPY_FILE_ID = UUID.fromString("20000000-0000-0000-0000-000000000009");

    @Mock
    private SearchableFileQuery searchableFileQuery;

    @Mock
    private SharedSpaceAccessQuery sharedSpaceAccessQuery;

    private FileSearchService service;

    @BeforeEach
    void setUp() {
        lenient().when(sharedSpaceAccessQuery.canBrowse(USER_ID)).thenReturn(false);
        service = new FileSearchService(searchableFileQuery, sharedSpaceAccessQuery);
    }

    @Test
    @DisplayName("按文件名命中当前活动文件，摘要为空")
    void returnsDatabaseTitleMatches() {
        when(searchableFileQuery.searchActiveFilesByName(USER_ID, "新名字", true, false, 50))
                .thenReturn(Map.of(ACTIVE_FILE_ID, "新名字.pdf"));

        List<SearchResultDto> results = service.search(USER_ID, " 新名字 ");

        assertThat(results).hasSize(1);
        assertThat(results.getFirst().fileId()).isEqualTo(ACTIVE_FILE_ID);
        assertThat(results.getFirst().title()).isEqualTo("新名字.pdf");
        assertThat(results.getFirst().snippet()).isNull();
        assertThat(results.getFirst().score()).isEqualTo(3.0);
    }

    @Test
    @DisplayName("同一关键词的多个文件各自成为独立结果")
    void everyMatchingFileBecomesItsOwnResult() {
        Map<UUID, String> matches = new LinkedHashMap<>();
        matches.put(ACTIVE_FILE_ID, "合同.pdf");
        matches.put(COPY_FILE_ID, "合同 (1).pdf");
        when(searchableFileQuery.searchActiveFilesByName(USER_ID, "合同", true, false, 50))
                .thenReturn(matches);

        List<SearchResultDto> results = service.search(USER_ID, "合同");

        assertThat(results).extracting(SearchResultDto::fileId)
                .containsExactly(ACTIVE_FILE_ID, COPY_FILE_ID);
        assertThat(results).extracting(SearchResultDto::title)
                .containsExactly("合同.pdf", "合同 (1).pdf");
    }

    @Test
    void blankQueryDoesNotAccessDatabase() {
        assertThat(service.search(USER_ID, "  ")).isEmpty();
        verifyNoInteractions(searchableFileQuery);
    }

    @Test
    void noTitleMatchReturnsEmptyResult() {
        when(searchableFileQuery.searchActiveFilesByName(USER_ID, "无此文件", true, false, 50))
                .thenReturn(Map.of());

        assertThat(service.search(USER_ID, "无此文件")).isEmpty();
    }

    @Test
    @DisplayName("无共享空间浏览权限时只查个人空间")
    void excludesSharedSpaceWhenBrowsingIsDenied() {
        when(searchableFileQuery.searchActiveFilesByName(USER_ID, "报告", true, false, 50))
                .thenReturn(Map.of(ACTIVE_FILE_ID, "报告.pdf"));

        service.search(USER_ID, "报告");

        verify(searchableFileQuery).searchActiveFilesByName(USER_ID, "报告", true, false, 50);
    }

    @Test
    @DisplayName("有共享空间浏览权限时同时查询个人与共享空间")
    void includesSharedSpaceWhenBrowsingIsAllowed() {
        when(sharedSpaceAccessQuery.canBrowse(USER_ID)).thenReturn(true);
        when(searchableFileQuery.searchActiveFilesByName(USER_ID, "报告", true, true, 50))
                .thenReturn(Map.of());

        assertThat(service.search(USER_ID, "报告")).isEmpty();

        verify(searchableFileQuery).searchActiveFilesByName(USER_ID, "报告", true, true, 50);
    }

    @Test
    @DisplayName("按 spaceType 过滤到共享空间")
    void filtersToSharedSpace() {
        when(sharedSpaceAccessQuery.canBrowse(USER_ID)).thenReturn(true);
        when(searchableFileQuery.searchActiveFilesByName(USER_ID, "报告", false, true, 50))
                .thenReturn(Map.of());

        assertThat(service.search(USER_ID, "报告", "SHARED")).isEmpty();

        verify(searchableFileQuery).searchActiveFilesByName(USER_ID, "报告", false, true, 50);
    }

    @Test
    void rejectsUnknownSpaceType() {
        assertThatThrownBy(() -> service.search(USER_ID, "报告", "UNKNOWN"))
                .isInstanceOf(BusinessException.class);
    }
}
