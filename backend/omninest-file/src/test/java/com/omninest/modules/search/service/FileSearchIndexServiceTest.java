package com.omninest.modules.search.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import java.util.stream.Stream;
import org.apache.lucene.analysis.standard.StandardAnalyzer;
import org.apache.lucene.index.IndexWriter;
import org.apache.lucene.index.IndexWriterConfig;
import org.apache.lucene.store.LockObtainFailedException;
import org.apache.lucene.store.NIOFSDirectory;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.CleanupMode;
import org.junit.jupiter.api.io.TempDir;

/**
 * FileSearchIndexService 单元测试。
 *
 * <p>正文索引只认不可变的内容对象标识，按用户目录物理隔离；文件名、节点标识与空间归属
 * 都在检索时回表解析，因此这里的断言只覆盖「哪些对象命中、命中了哪一段」。</p>
 *
 * @author OmniNest
 */
class FileSearchIndexServiceTest {

    @TempDir(cleanup = CleanupMode.NEVER)
    Path tempDir;

    private FileSearchIndexService service;

    private static final UUID USER_A = UUID.fromString("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static final UUID USER_B = UUID.fromString("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    @BeforeEach
    void setUp() throws Exception {
        service = new FileSearchIndexService(tempDir.toString(), 64);
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

    private void index(UUID objectId, UUID owner, String space, String... chunks) {
        service.indexObjectChunks(objectId, owner, space, List.of(chunks));
    }

    @Test
    @DisplayName("正文检索只返回指定用户目录里的对象")
    void searchOnlyReturnsObjectsFromTheSpecifiedUserDirectory() {
        UUID objectA = UUID.randomUUID();
        UUID objectB = UUID.randomUUID();
        index(objectA, USER_A, "PERSONAL", "第一季度工作总结");
        index(objectB, USER_B, "PERSONAL", "第二季度工作计划");

        assertThat(service.search(USER_A, "工作总结", 50))
                .extracting(FileSearchIndexService.FileContentHit::fileObjectId)
                .containsExactly(objectA);
        assertThat(service.search(USER_B, "工作总结", 50)).isEmpty();
    }

    @Test
    @DisplayName("共享目录对任一成员可见，但只在请求共享空间时命中")
    void sharedObjectsLiveInTheGlobalDirectory() {
        UUID objectId = UUID.randomUUID();
        index(objectId, USER_A, "SHARED", "共享项目的第一季度正文");

        assertThat(service.search(USER_B, "第一季度", 10, "SHARED"))
                .extracting(FileSearchIndexService.FileContentHit::fileObjectId)
                .containsExactly(objectId);
        assertThat(service.search(USER_B, "第一季度", 10, "PERSONAL")).isEmpty();
        assertThat(service.search(USER_B, "第一季度", 10))
                .extracting(FileSearchIndexService.FileContentHit::fileObjectId)
                .containsExactly(objectId);
    }

    @Test
    @DisplayName("同一内容对象重复索引时旧分块被替换，不产生重复文档")
    void reindexingSameObjectReplacesPreviousChunks() {
        UUID objectId = UUID.randomUUID();
        index(objectId, USER_A, "PERSONAL", "旧稿第一章 山洪爆发", "旧稿第二章 抢险记录");

        index(objectId, USER_A, "PERSONAL", "新稿第三章 晴日");

        assertThat(service.search(USER_A, "山洪", 50)).isEmpty();
        assertThat(service.search(USER_A, "晴日", 50))
                .extracting(FileSearchIndexService.FileContentHit::fileObjectId)
                .containsExactly(objectId);
        assertThat(service.clearIndex(USER_A)).isEqualTo(1);
    }

    @Test
    @DisplayName("多关键词按词元组合匹配，不要求词元在原文中相邻")
    void multiKeywordQueryCombinesTokens() {
        UUID objectId = UUID.randomUUID();
        index(objectId, USER_A, "PERSONAL", "2026 年度报告，财务 分析");

        assertThat(service.search(USER_A, "2026 财务", 10))
                .extracting(FileSearchIndexService.FileContentHit::fileObjectId)
                .containsExactly(objectId);
    }

    @Test
    @DisplayName("命中结果返回正文摘要而不是恒定 null")
    void searchReturnsStoredSnippet() {
        UUID objectId = UUID.randomUUID();
        index(objectId, USER_A, "PERSONAL", "这是用于摘要展示的正文内容，包含季度财务分析。");

        List<FileSearchIndexService.FileContentHit> hits = service.search(USER_A, "季度财务", 10);

        assertThat(hits).hasSize(1);
        assertThat(hits.getFirst().snippet()).contains("季度财务");
    }

    @Test
    @DisplayName("分块会话在 complete 前对外不可见，提交后一次生效")
    void chunkSessionIsInvisibleUntilCompleted() throws Exception {
        UUID objectId = UUID.randomUUID();
        FileSearchIndexService.ChunkIndexSession session =
                service.openChunkIndex(objectId, USER_A, "PERSONAL");
        session.append("第一章 山洪爆发了");
        session.append("第二章 抢险记录");

        // 另一个只读实例代表检索侧：没有 commit 就看不到半成品正文。
        try (FileSearchIndexService reader = new FileSearchIndexService(tempDir.toString(), 64)) {
            assertThat(reader.search(USER_A, "山洪", 10)).isEmpty();
            assertThat(session.complete()).isEqualTo(2);
            assertThat(reader.search(USER_A, "山洪", 10))
                    .extracting(FileSearchIndexService.FileContentHit::fileObjectId)
                    .containsExactly(objectId);
        }
    }

    @Test
    @DisplayName("无正文的分块会话不写文档，文件名检索不依赖索引")
    void emptyChunkSessionWritesNothing() {
        UUID objectId = UUID.randomUUID();
        FileSearchIndexService.ChunkIndexSession session =
                service.openChunkIndex(objectId, USER_A, "PERSONAL");

        assertThat(session.complete()).isZero();
        assertThat(service.clearIndex(USER_A)).isZero();
    }

    @Test
    @DisplayName("deleteObjects 只删除指定对象，两个目录一并清理")
    void deleteObjectsRemovesBothSpaceDirectories() {
        UUID personal = UUID.randomUUID();
        UUID shared = UUID.randomUUID();
        index(personal, USER_A, "PERSONAL", "个人空间的待删除正文");
        index(shared, USER_A, "SHARED", "共享空间的待删除正文");

        service.deleteObjects(List.of(personal, shared), USER_A);

        assertThat(service.search(USER_A, "待删除", 10)).isEmpty();
    }

    @Test
    @DisplayName("删除不存在的对象不抛异常")
    void deleteObjectsForUnknownObjectDoesNotThrow() {
        service.deleteObjects(List.of(UUID.randomUUID()), USER_A);
    }

    @Test
    @DisplayName("clearIndex 只清空指定用户目录")
    void clearIndexOnlyClearsSpecifiedUser() {
        index(UUID.randomUUID(), USER_A, "PERSONAL", "内容A");
        UUID objectB = UUID.randomUUID();
        index(objectB, USER_B, "PERSONAL", "内容B");

        assertThat(service.clearIndex(USER_A)).isEqualTo(1);

        assertThat(service.search(USER_A, "内容", 50)).isEmpty();
        assertThat(service.search(USER_B, "内容", 50))
                .extracting(FileSearchIndexService.FileContentHit::fileObjectId)
                .containsExactly(objectB);
    }

    @Test
    @DisplayName("clearAllIndexes 清除所有目录并回收墓碑")
    void clearAllIndexesClearsEveryDirectory() {
        index(UUID.randomUUID(), USER_A, "PERSONAL", "内容A");
        index(UUID.randomUUID(), USER_B, "PERSONAL", "内容B");

        assertThat(service.clearAllIndexes()).isEqualTo(2);

        assertThat(service.search(USER_A, "内容", 50)).isEmpty();
        assertThat(service.search(USER_B, "内容", 50)).isEmpty();
    }

    @Test
    @DisplayName("每个用户目录在磁盘上独立创建")
    void perUserDirectoriesAreCreatedIndependently() {
        index(UUID.randomUUID(), USER_A, "PERSONAL", "内容");
        index(UUID.randomUUID(), USER_B, "PERSONAL", "内容");

        assertThat(Files.isDirectory(tempDir.resolve(USER_A.toString()))).isTrue();
        assertThat(Files.isDirectory(tempDir.resolve(USER_B.toString()))).isTrue();
    }

    @Test
    @DisplayName("hasObjectContent 能区分已索引与未索引的对象")
    void hasObjectContentReflectsIndexedObjects() {
        UUID indexed = UUID.randomUUID();
        index(indexed, USER_A, "PERSONAL", "已经索引的正文");

        assertThat(service.hasObjectContent(USER_A, "PERSONAL", indexed)).isTrue();
        assertThat(service.hasObjectContent(USER_A, "PERSONAL", UUID.randomUUID())).isFalse();
        assertThat(service.hasObjectContent(USER_B, "PERSONAL", indexed)).isFalse();
    }

    @Test
    @DisplayName("另一写者持有 write.lock 时搜索仍返回命中")
    void searchReturnsHitsWhileAnotherWriterHoldsWriteLock() throws Exception {
        UUID objectId = UUID.randomUUID();
        FileSearchIndexService writerSide = new FileSearchIndexService(tempDir.toString(), 64);
        writerSide.indexObjectChunks(objectId, USER_A, "PERSONAL", List.of("山间晨雾"));
        writerSide.close();

        Path userDir = tempDir.resolve(USER_A.toString());
        try (StandardAnalyzer analyzer = new StandardAnalyzer();
             NIOFSDirectory otherProcessDir = new NIOFSDirectory(userDir);
             IndexWriter otherProcessWriter = new IndexWriter(otherProcessDir, new IndexWriterConfig(analyzer))) {

            // 先证明这把锁真的被占住：否则下面的断言只是「无锁也能读」，钉不住单写进程的约束。
            assertThatThrownBy(() -> new IndexWriter(
                    new NIOFSDirectory(userDir), new IndexWriterConfig(new StandardAnalyzer())))
                    .isInstanceOf(LockObtainFailedException.class);

            FileSearchIndexService requestSide = new FileSearchIndexService(tempDir.toString(), 64);
            try {
                assertThat(requestSide.search(USER_A, "山间晨雾", 10))
                        .extracting(FileSearchIndexService.FileContentHit::fileObjectId)
                        .containsExactly(objectId);
            } finally {
                requestSide.close();
            }
        }
    }

    @Test
    @DisplayName("删除用户索引后墓碑阻止重建，直到管理员全量重建")
    void purgedUserCannotRecreateIndexUntilFullRebuild() throws Exception {
        index(UUID.randomUUID(), USER_A, "PERSONAL", "待删除索引的正文");

        assertThat(service.deleteUserIndex(USER_A)).isTrue();
        assertThat(service.isUserPurged(USER_A)).isTrue();

        service.indexObjectChunks(UUID.randomUUID(), USER_A, "PERSONAL", List.of("删除后重建的正文"));
        assertThat(Files.exists(tempDir.resolve(USER_A.toString()))).isFalse();
        assertThat(service.search(USER_A, "删除后重建", 10)).isEmpty();

        service.clearAllIndexes();
        assertThat(service.isUserPurged(USER_A)).isFalse();
    }

    @Test
    @DisplayName("SearcherManager 缓存能感知清空与重新提交的新段")
    void searchManagerSeesClearAndNewCommits() {
        UUID first = UUID.randomUUID();
        index(first, USER_A, "PERSONAL", "缓存刷新前的内容");
        assertThat(service.search(USER_A, "缓存刷新前", 10))
                .extracting(FileSearchIndexService.FileContentHit::fileObjectId)
                .containsExactly(first);

        assertThat(service.clearIndex(USER_A)).isEqualTo(1);
        assertThat(service.search(USER_A, "缓存刷新前", 10)).isEmpty();

        UUID second = UUID.randomUUID();
        index(second, USER_A, "PERSONAL", "重新提交后的内容");
        assertThat(service.search(USER_A, "重新提交", 10))
                .extracting(FileSearchIndexService.FileContentHit::fileObjectId)
                .containsExactly(second);
    }

    @Test
    @DisplayName("用户索引缓存超过容量后关闭旧资源并可从磁盘重新打开")
    void indexCacheEvictsAndReopensFromDisk() throws Exception {
        service.close();
        service = new FileSearchIndexService(tempDir.toString(), 2);
        UUID persisted = UUID.randomUUID();
        index(persisted, USER_A, "PERSONAL", "缓存淘汰后仍可搜索");
        index(UUID.randomUUID(), USER_B, "PERSONAL", "内容B");
        index(UUID.randomUUID(), UUID.randomUUID(), "PERSONAL", "内容C");

        assertThat(service.cachedUserIndexCount()).isLessThanOrEqualTo(2);
        assertThat(service.search(USER_A, "缓存淘汰", 10))
                .extracting(FileSearchIndexService.FileContentHit::fileObjectId)
                .containsExactly(persisted);
        assertThat(service.cachedUserIndexCount()).isLessThanOrEqualTo(2);
    }
}
