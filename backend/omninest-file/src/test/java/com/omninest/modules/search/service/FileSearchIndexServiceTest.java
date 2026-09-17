package com.omninest.modules.search.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.search.dto.SearchResultDto;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import java.util.stream.Stream;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.CleanupMode;
import org.junit.jupiter.api.io.TempDir;

/**
 * FileSearchIndexService 单元测试。
 * 验证按用户隔离的 Lucene 索引目录行为。
 */
class FileSearchIndexServiceTest {

    @TempDir(cleanup = CleanupMode.NEVER)
    Path tempDir;

    private FileSearchIndexService service;

    private static final UUID USER_A = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID USER_B = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    @BeforeEach
    void setUp() throws Exception {
        service = new FileSearchIndexService(tempDir.toString());
    }

    @AfterEach
    void tearDown() throws Exception {
        service.close();
        deleteTempDirWithRetry();
    }

    /**
     * Windows 上 Lucene 关闭后句柄释放可能略有延迟，JUnit 默认清理会偶发失败。
     */
    private void deleteTempDirWithRetry() throws Exception {
        IOException last = null;
        for (int attempt = 0; attempt < 20; attempt++) {
            try {
                if (!Files.exists(tempDir)) {
                    return;
                }
                try (Stream<Path> walk = Files.walk(tempDir)) {
                    walk.sorted(Comparator.reverseOrder()).forEach(path -> {
                        try {
                            Files.deleteIfExists(path);
                        } catch (IOException e) {
                            throw new RuntimeException(e);
                        }
                    });
                }
                return;
            } catch (RuntimeException e) {
                if (e.getCause() instanceof IOException io) {
                    last = io;
                } else {
                    throw e;
                }
            } catch (IOException e) {
                last = e;
            }
            Thread.sleep(50L);
        }
        if (last != null) {
            throw last;
        }
    }

    @Test
    @DisplayName("搜索仅返回指定用户的结果，不包含其他用户的文档")
    void search_onlyReturnsResultsForSpecifiedUser() {
        // 为 userA 索引两份文档
        UUID fileIdA1 = UUID.randomUUID();
        UUID fileIdA2 = UUID.randomUUID();
        service.indexFile(fileIdA1, USER_A, "项目报告", "第一季度工作总结");
        service.indexFile(fileIdA2, USER_A, "会议纪要", "团队周会讨论内容");

        // 为 userB 索引一份文档
        UUID fileIdB1 = UUID.randomUUID();
        service.indexFile(fileIdB1, USER_B, "项目报告", "第二季度工作计划");

        // 以 userA 身份搜索"项目报告"
        List<SearchResultDto> resultsA = service.search(USER_A, "项目报告", 50);
        assertThat(resultsA).hasSize(1);
        assertThat(resultsA.get(0).fileId()).isEqualTo(fileIdA1);

        // 以 userB 身份搜索"项目报告"
        List<SearchResultDto> resultsB = service.search(USER_B, "项目报告", 50);
        assertThat(resultsB).hasSize(1);
        assertThat(resultsB.get(0).fileId()).isEqualTo(fileIdB1);
    }

    @Test
    @DisplayName("搜索不同用户共享关键词时互不干扰")
    void search_differentUsersWithSameKeyword_doNotLeak() {
        UUID fileIdA = UUID.randomUUID();
        UUID fileIdB = UUID.randomUUID();
        service.indexFile(fileIdA, USER_A, "机密文档", "仅供内部使用");
        service.indexFile(fileIdB, USER_B, "机密文档", "外部共享版本");

        // userA 搜索"机密文档"只能看到自己的
        List<SearchResultDto> resultsA = service.search(USER_A, "机密文档", 50);
        assertThat(resultsA).hasSize(1);
        assertThat(resultsA.get(0).fileId()).isEqualTo(fileIdA);

        // userB 搜索"机密文档"只能看到自己的
        List<SearchResultDto> resultsB = service.search(USER_B, "机密文档", 50);
        assertThat(resultsB).hasSize(1);
        assertThat(resultsB.get(0).fileId()).isEqualTo(fileIdB);
    }

    @Test
    @DisplayName("clearIndex 仅清除指定用户的索引，不影响其他用户")
    void clearIndex_onlyClearsSpecifiedUserIndex() {
        UUID fileIdA = UUID.randomUUID();
        UUID fileIdB = UUID.randomUUID();
        service.indexFile(fileIdA, USER_A, "用户A的文件", "内容A");
        service.indexFile(fileIdB, USER_B, "用户B的文件", "内容B");

        // 清除 userA 的索引
        int cleared = service.clearIndex(USER_A);
        assertThat(cleared).isEqualTo(1);

        // userA 搜索不到任何结果
        List<SearchResultDto> resultsA = service.search(USER_A, "文件", 50);
        assertThat(resultsA).isEmpty();

        // userB 的索引不受影响
        List<SearchResultDto> resultsB = service.search(USER_B, "文件", 50);
        assertThat(resultsB).hasSize(1);
        assertThat(resultsB.get(0).fileId()).isEqualTo(fileIdB);
    }

    @Test
    @DisplayName("deleteFile 仅从指定用户的索引中删除文档")
    void deleteFile_onlyDeletesFromSpecifiedUserIndex() {
        UUID fileIdA = UUID.randomUUID();
        UUID fileIdB = UUID.randomUUID();
        service.indexFile(fileIdA, USER_A, "待删除文件", "内容A");
        service.indexFile(fileIdB, USER_B, "待删除文件", "内容B");

        // 仅删除 userA 的文档
        service.deleteFile(fileIdA, USER_A);

        // userA 搜索不到已删除的文档
        List<SearchResultDto> resultsA = service.search(USER_A, "待删除", 50);
        assertThat(resultsA).isEmpty();

        // userB 的同名文档不受影响
        List<SearchResultDto> resultsB = service.search(USER_B, "待删除", 50);
        assertThat(resultsB).hasSize(1);
        assertThat(resultsB.get(0).fileId()).isEqualTo(fileIdB);
    }

    @Test
    @DisplayName("clearAllIndexes 清除所有用户索引")
    void clearAllIndexes_clearsAllUserIndexes() {
        service.indexFile(UUID.randomUUID(), USER_A, "文件A", "内容A");
        service.indexFile(UUID.randomUUID(), USER_B, "文件B", "内容B");

        int totalCleared = service.clearAllIndexes();
        assertThat(totalCleared).isEqualTo(2);

        // 两个用户的索引都应为空
        assertThat(service.search(USER_A, "文件", 50)).isEmpty();
        assertThat(service.search(USER_B, "文件", 50)).isEmpty();
    }

    @Test
    @DisplayName("更新同 fileId 的文档后搜索返回最新内容")
    void indexFile_sameFileId_updatesExistingDocument() {
        UUID fileId = UUID.randomUUID();
        service.indexFile(fileId, USER_A, "旧标题", "旧内容");
        service.indexFile(fileId, USER_A, "新标题", "新内容");

        List<SearchResultDto> results = service.search(USER_A, "新标题", 50);
        assertThat(results).hasSize(1);
        assertThat(results.get(0).fileId()).isEqualTo(fileId);

        // 旧标题不应再被搜到
        assertThat(service.search(USER_A, "旧标题", 50)).isEmpty();
    }

    @Test
    @DisplayName("每个用户索引目录在磁盘上独立创建")
    void indexFile_createsPerUserDirectoriesOnDisk() {
        service.indexFile(UUID.randomUUID(), USER_A, "测试文件", "内容");
        service.indexFile(UUID.randomUUID(), USER_B, "测试文件", "内容");

        Path userPathA = tempDir.resolve(USER_A.toString());
        Path userPathB = tempDir.resolve(USER_B.toString());
        assertThat(Files.isDirectory(userPathA)).isTrue();
        assertThat(Files.isDirectory(userPathB)).isTrue();
        assertThat(userPathA).isNotEqualTo(userPathB);
    }

    @Test
    @DisplayName("搜索不存在的用户返回空结果")
    void search_nonExistentUser_returnsEmpty() {
        UUID unknownUser = UUID.randomUUID();
        List<SearchResultDto> results = service.search(unknownUser, "任何关键词", 50);
        assertThat(results).isEmpty();
    }

    @Test
    @DisplayName("删除不存在的文档不抛异常")
    void deleteFile_nonExistentDocument_doesNotThrow() {
        UUID unknownFile = UUID.randomUUID();
        // 内部 catch 异常并记录日志，不向外抛出
        service.deleteFile(unknownFile, USER_A);
        // 无异常即通过
    }

    @Test
    @DisplayName("用户索引缓存超过容量后关闭旧资源并可从磁盘重新打开")
    void indexCache_exceedsCapacity_evictsAndReopensIndex() throws Exception {
        service.close();
        service = new FileSearchIndexService(tempDir.toString(), 2);
        UUID firstFileId = UUID.randomUUID();
        service.indexFile(firstFileId, USER_A, "持久索引", "缓存淘汰后仍可搜索");
        service.indexFile(UUID.randomUUID(), USER_B, "用户B", "内容B");
        service.indexFile(UUID.randomUUID(), UUID.randomUUID(), "用户C", "内容C");

        assertThat(service.cachedUserIndexCount()).isLessThanOrEqualTo(2);
        assertThat(service.search(USER_A, "持久索引", 10))
                .extracting(SearchResultDto::fileId)
                .containsExactly(firstFileId);
        assertThat(service.cachedUserIndexCount()).isLessThanOrEqualTo(2);
    }

}
