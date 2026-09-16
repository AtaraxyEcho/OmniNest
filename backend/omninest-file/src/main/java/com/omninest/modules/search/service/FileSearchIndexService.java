package com.omninest.modules.search.service;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.github.benmanes.caffeine.cache.RemovalListener;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.search.dto.SearchResultDto;
import java.io.Closeable;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import org.apache.lucene.analysis.cn.smart.SmartChineseAnalyzer;
import org.apache.lucene.document.Document;
import org.apache.lucene.document.Field;
import org.apache.lucene.document.StringField;
import org.apache.lucene.document.TextField;
import org.apache.lucene.index.DirectoryReader;
import org.apache.lucene.index.IndexNotFoundException;
import org.apache.lucene.index.IndexWriter;
import org.apache.lucene.index.IndexWriterConfig;
import org.apache.lucene.index.Term;
import org.apache.lucene.queryparser.classic.QueryParser;
import org.apache.lucene.search.BooleanClause;
import org.apache.lucene.search.BooleanQuery;
import org.apache.lucene.search.IndexSearcher;
import org.apache.lucene.search.Query;
import org.apache.lucene.search.ScoreDoc;
import org.apache.lucene.search.TermQuery;
import org.apache.lucene.search.TopDocs;
import org.apache.lucene.store.Directory;
import org.apache.lucene.store.MMapDirectory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * 文件搜索索引服务，使用按用户隔离的 Lucene 索引目录。
 * 每个用户拥有独立的索引目录，防止跨用户搜索数据泄漏。
 */
@Slf4j
@Service
public class FileSearchIndexService implements Closeable {
    private static final String FIELD_FILE_ID = "fileId";
    private static final String FIELD_TITLE = "title";
    private static final String FIELD_CONTENT = "content";
    private static final String FIELD_SPACE_TYPE = "spaceType";
    private static final String FIELD_HAS_CONTENT = "hasContent";
    private static final String HAS_CONTENT_YES = "Y";
    private static final String HAS_CONTENT_NO = "N";
    private static final long MAX_CACHED_USER_INDEXES = 64;
    private static final Duration USER_INDEX_IDLE_TTL = Duration.ofMinutes(30);

    private final Path basePath;
    private final SmartChineseAnalyzer analyzer = new SmartChineseAnalyzer();

    /** 按用户缓存的索引状态，淘汰时同步关闭 Lucene 资源。 */
    private final Cache<UUID, UserIndexState> userIndexes;

    @Autowired
    public FileSearchIndexService(
            @Value("${omninest.search.index-path:${user.home}/.omninest/lucene-index}") String indexPath
    ) throws IOException {
        this(indexPath, MAX_CACHED_USER_INDEXES);
    }

    FileSearchIndexService(String indexPath, long maxCachedUserIndexes) throws IOException {
        this.basePath = Path.of(indexPath);
        Files.createDirectories(this.basePath);
        RemovalListener<UUID, UserIndexState> removalListener =
                (userId, state, cause) -> closeUserIndex(state);
        this.userIndexes = Caffeine.<UUID, UserIndexState>newBuilder()
                .maximumSize(maxCachedUserIndexes)
                .expireAfterAccess(USER_INDEX_IDLE_TTL)
                .executor(Runnable::run)
                .removalListener(removalListener)
                .build();
    }

    /**
     * 获取指定用户的索引目录路径。
     */
    private Path getUserIndexPath(UUID userId) {
        return basePath.resolve(userId.toString());
    }

    /**
     * 获取或创建指定用户的索引写入器。
     * 懒加载：首次访问时创建 Directory 和 IndexWriter。
     * 使用 computeIfAbsent 保证线程安全，避免并发创建导致资源泄漏。
     */
    private UserIndexState getUserIndexState(UUID userId) throws IOException {
        try {
            return userIndexes.get(userId, id -> {
                try {
                    Path userPath = getUserIndexPath(id);
                    Files.createDirectories(userPath);
                    Directory directory = new MMapDirectory(userPath);
                    IndexWriter writer = new IndexWriter(directory, new IndexWriterConfig(analyzer));
                    return new UserIndexState(directory, writer);
                } catch (IOException e) {
                    throw new UncheckedIOException(e);
                }
            });
        } catch (UncheckedIOException e) {
            throw e.getCause();
        }
    }

    private <T> T withUserIndexState(UUID userId, UserIndexOperation<T> operation) throws Exception {
        while (true) {
            UserIndexState state = getUserIndexState(userId);
            synchronized (state) {
                if (state.closed) {
                    continue;
                }
                return operation.execute(state);
            }
        }
    }

    /**
     * 打开指定用户索引的只读 NRT reader。
     * 使用 DirectoryReader.open(writer) 获取近实时 reader，正确处理 Lucene 10 软删除。
     * 如果索引目录为空或不存在，返回 null。
     * 调用方负责在使用完毕后关闭 reader。
     */
    private DirectoryReader openReaderOrNull(UserIndexState state) throws IOException {
        try {
            return DirectoryReader.open(state.writer);
        } catch (IndexNotFoundException e) {
            return null;
        }
    }

    /**
     * 索引文件文档，已存在同 fileId 文档则更新。
     *
     * @param fileNodeId  文件节点 ID
     * @param ownerUserId 拥有者用户 ID
     * @param title       文件标题
     * @param content     可选的文本内容
     */
    public void indexFile(UUID fileNodeId, UUID ownerUserId, String title, String content) {
        indexFile(fileNodeId, ownerUserId, title, content, "PERSONAL");
    }

    /**
     * 索引文件文档，已存在同 fileId 文档则更新。
     *
     * @param fileNodeId  文件节点 ID
     * @param ownerUserId 拥有者用户 ID
     * @param title       文件标题
     * @param content     可选的文本内容
     * @param spaceType   空间类型（PERSONAL / SHARED）
     */
    public void indexFile(UUID fileNodeId, UUID ownerUserId, String title, String content, String spaceType) {
        boolean hasContent = content != null && !content.isBlank();
        try {
            withUserIndexState(ownerUserId, state -> {
                // FILE_INDEX 仅写元数据；若 TEXT_EXTRACTION 已写入正文，不得覆盖清空。
                if (!hasContent && alreadyHasContent(state, fileNodeId)) {
                    return null;
                }
                Document doc = new Document();
                // fileId 使用 StringField，确保 Term 精确匹配删除能正确工作。
                doc.add(new StringField(FIELD_FILE_ID, fileNodeId.toString(), Field.Store.YES));
                doc.add(new TextField(FIELD_TITLE, title, Field.Store.YES));
                doc.add(new StringField(FIELD_SPACE_TYPE, spaceType, Field.Store.YES));
                doc.add(new StringField(
                        FIELD_HAS_CONTENT,
                        hasContent ? HAS_CONTENT_YES : HAS_CONTENT_NO,
                        Field.Store.YES
                ));
                if (hasContent) {
                    doc.add(new TextField(FIELD_CONTENT, content, Field.Store.NO));
                }
                // 显式删除后新增，避免 Lucene 软删除使旧文档继续参与搜索。
                state.writer.deleteDocuments(new Term(FIELD_FILE_ID, fileNodeId.toString()));
                state.writer.addDocument(doc);
                state.writer.commit();
                return null;
            });
            log.debug(
                    "索引文件: fileNodeId={}, ownerUserId={}, title={}, spaceType={}",
                    fileNodeId, ownerUserId, title, spaceType
            );
        } catch (Exception e) {
            log.warn("Lucene 索引写入失败: fileNodeId={}, ownerUserId={}", fileNodeId, ownerUserId, e);
        }
    }

    /**
     * 删除指定用户的文件索引。
     *
     * @param fileNodeId  文件节点 ID
     * @param ownerUserId 拥有者用户 ID
     */
    private boolean alreadyHasContent(UserIndexState state, UUID fileNodeId) throws IOException {
        try (DirectoryReader reader = openReaderOrNull(state)) {
            if (reader == null) {
                return false;
            }
            IndexSearcher searcher = new IndexSearcher(reader);
            Query query = new BooleanQuery.Builder()
                    .add(new TermQuery(new Term(FIELD_FILE_ID, fileNodeId.toString())), BooleanClause.Occur.MUST)
                    .add(new TermQuery(new Term(FIELD_HAS_CONTENT, HAS_CONTENT_YES)), BooleanClause.Occur.MUST)
                    .build();
            return searcher.count(query) > 0;
        }
    }

    /**
     * 删除指定用户的文件索引。
     *
     * @param fileNodeId  文件节点 ID
     * @param ownerUserId 拥有者用户 ID
     */
    public void deleteFile(UUID fileNodeId, UUID ownerUserId) {
        try {
            withUserIndexState(ownerUserId, state -> {
                state.writer.deleteDocuments(new Term(FIELD_FILE_ID, fileNodeId.toString()));
                state.writer.commit();
                return null;
            });
            log.debug("删除索引: fileNodeId={}, ownerUserId={}", fileNodeId, ownerUserId);
        } catch (Exception e) {
            log.warn("Lucene 索引删除失败: fileNodeId={}, ownerUserId={}", fileNodeId, ownerUserId, e);
        }
    }

    /**
     * 批量删除指定用户的文件索引，一次 commit 减少 fsync 次数。
     *
     * @param fileNodeIds 文件节点 ID 集合
     * @param ownerUserId 拥有者用户 ID
     */
    public void deleteFiles(Collection<UUID> fileNodeIds, UUID ownerUserId) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return;
        }
        try {
            withUserIndexState(ownerUserId, state -> {
                for (UUID fileNodeId : fileNodeIds) {
                    state.writer.deleteDocuments(new Term(FIELD_FILE_ID, fileNodeId.toString()));
                }
                state.writer.commit();
                return null;
            });
            log.debug("批量删除索引: count={}, ownerUserId={}", fileNodeIds.size(), ownerUserId);
        } catch (Exception e) {
            log.warn("Lucene 索引批量删除失败: count={}, ownerUserId={}", fileNodeIds.size(), ownerUserId, e);
        }
    }

    /**
     * 批量索引文件文档，一次 commit 减少 fsync 次数。
     * 每个条目提供 fileNodeId、title、content 与 spaceType；content 可为 null。
     *
     * @param ownerUserId 拥有者用户 ID
     * @param docs 待索引文档集合
     */
    public void indexFiles(UUID ownerUserId, Collection<IndexDocumentInput> docs) {
        if (docs == null || docs.isEmpty()) {
            return;
        }
        try {
            withUserIndexState(ownerUserId, state -> {
                for (IndexDocumentInput input : docs) {
                    Document doc = new Document();
                    doc.add(new StringField(FIELD_FILE_ID, input.fileNodeId().toString(), Field.Store.YES));
                    doc.add(new TextField(FIELD_TITLE, input.title(), Field.Store.YES));
                    doc.add(new StringField(FIELD_SPACE_TYPE, input.spaceType(), Field.Store.YES));
                    if (input.content() != null && !input.content().isBlank()) {
                        doc.add(new TextField(FIELD_CONTENT, input.content(), Field.Store.NO));
                    }
                    state.writer.deleteDocuments(new Term(FIELD_FILE_ID, input.fileNodeId().toString()));
                    state.writer.addDocument(doc);
                }
                state.writer.commit();
                return null;
            });
            log.debug("批量索引文件: count={}, ownerUserId={}", docs.size(), ownerUserId);
        } catch (Exception e) {
            log.warn("Lucene 索引批量写入失败: count={}, ownerUserId={}", docs.size(), ownerUserId, e);
        }
    }

    /**
     * 分块索引超长文本文件。
     *
     * <p>千万字级网文无法塞进单条 Lucene 文档；按块写入多个同 fileId 文档，
     * 删除时按 fileId 整批清除，搜索命中后按文件去重。</p>
     *
     * @param fileNodeId 文件节点 ID
     * @param ownerUserId 拥有者用户 ID
     * @param title 文件标题
     * @param chunks 文本分块，按原文顺序
     * @param spaceType 空间类型
     */
    public void indexFileChunks(
            UUID fileNodeId,
            UUID ownerUserId,
            String title,
            List<String> chunks,
            String spaceType
    ) {
        if (chunks == null || chunks.isEmpty()) {
            indexFile(fileNodeId, ownerUserId, title, null, spaceType);
            return;
        }
        try {
            withUserIndexState(ownerUserId, state -> {
                state.writer.deleteDocuments(new Term(FIELD_FILE_ID, fileNodeId.toString()));
                for (String chunk : chunks) {
                    if (chunk == null || chunk.isBlank()) {
                        continue;
                    }
                    Document doc = new Document();
                    doc.add(new StringField(FIELD_FILE_ID, fileNodeId.toString(), Field.Store.YES));
                    doc.add(new TextField(FIELD_TITLE, title, Field.Store.YES));
                    doc.add(new StringField(FIELD_SPACE_TYPE, spaceType, Field.Store.YES));
                    doc.add(new StringField(FIELD_HAS_CONTENT, HAS_CONTENT_YES, Field.Store.YES));
                    doc.add(new TextField(FIELD_CONTENT, chunk, Field.Store.NO));
                    state.writer.addDocument(doc);
                }
                state.writer.commit();
                return null;
            });
            log.debug(
                    "分块索引文件: fileNodeId={}, ownerUserId={}, chunkCount={}, spaceType={}",
                    fileNodeId, ownerUserId, chunks.size(), spaceType
            );
        } catch (Exception e) {
            log.warn("Lucene 分块索引写入失败: fileNodeId={}, ownerUserId={}", fileNodeId, ownerUserId, e);
        }
    }

    /**
     * 批量索引文档条目。
     *
     * @param fileNodeId 文件节点 ID
     * @param title 文件标题
     * @param content 可选文本内容
     * @param spaceType 空间类型（PERSONAL / SHARED）
     */
    public record IndexDocumentInput(
            UUID fileNodeId,
            String title,
            String content,
            String spaceType
    ) {
    }

    /**
     * 在指定用户的索引中搜索文件（仅个人空间）。
     *
     * @param ownerUserId 拥有者用户 ID
     * @param queryStr    搜索关键词
     * @param maxResults  最大返回数量
     * @return 搜索结果列表
     */
    public List<SearchResultDto> search(UUID ownerUserId, String queryStr, int maxResults) {
        return search(ownerUserId, queryStr, maxResults, "PERSONAL");
    }

    /**
     * 在指定用户的索引中搜索文件。
     *
     * @param ownerUserId 拥有者用户 ID
     * @param queryStr    搜索关键词
     * @param maxResults  最大返回数量
     * @param spaceType   空间类型过滤（PERSONAL / SHARED / null 表示全部）
     * @return 搜索结果列表
     */
    public List<SearchResultDto> search(UUID ownerUserId, String queryStr, int maxResults, String spaceType) {
        try {
            return withUserIndexState(ownerUserId, state -> {
                List<SearchResultDto> results = new ArrayList<>();
                try (DirectoryReader reader = openReaderOrNull(state)) {
                    if (reader == null) {
                        return results;
                    }
                    IndexSearcher searcher = new IndexSearcher(reader);
                    QueryParser parser = new QueryParser(FIELD_TITLE, analyzer);
                    String escaped = QueryParser.escape(queryStr);
                    String fullQuery;
                    if (spaceType != null) {
                        fullQuery = String.format("%s:\"%s\" %s:\"%s\" %s:\"%s\"",
                                FIELD_TITLE, escaped, FIELD_CONTENT, escaped,
                                FIELD_SPACE_TYPE, spaceType);
                    } else {
                        fullQuery = String.format("%s:\"%s\" %s:\"%s\"",
                                FIELD_TITLE, escaped, FIELD_CONTENT, escaped);
                    }
                    Query query = parser.parse(fullQuery);
                    // 超长文件分块后同一 fileId 会命中多条文档，放宽候选后再按文件去重。
                    int candidateLimit = Math.max(maxResults * 8, maxResults);
                    TopDocs topDocs = searcher.search(query, candidateLimit);
                    Map<UUID, Float> bestScores = new LinkedHashMap<>();
                    Map<UUID, String> titles = new LinkedHashMap<>();
                    for (ScoreDoc scoreDoc : topDocs.scoreDocs) {
                        Document doc = searcher.storedFields().document(scoreDoc.doc);
                        UUID fileId = UUID.fromString(doc.get(FIELD_FILE_ID));
                        String title = doc.get(FIELD_TITLE);
                        Float existing = bestScores.get(fileId);
                        if (existing == null || scoreDoc.score > existing) {
                            bestScores.put(fileId, scoreDoc.score);
                            titles.put(fileId, title);
                        }
                    }
                    int added = 0;
                    for (Map.Entry<UUID, Float> entry : bestScores.entrySet()) {
                        if (added >= maxResults) {
                            break;
                        }
                        results.add(new SearchResultDto(
                                entry.getKey(),
                                titles.get(entry.getKey()),
                                null,
                                entry.getValue()
                        ));
                        added++;
                    }
                }
                return results;
            });
        } catch (Exception e) {
            log.warn("Lucene 搜索失败: ownerUserId={}, queryLength={}, errorType={}",
                    ownerUserId, queryStr.length(), e.getClass().getSimpleName());
            return new ArrayList<>();
        }
    }

    /**
     * 清空指定用户的索引内容。
     * 返回清空前的文档数量。
     *
     * @param ownerUserId 拥有者用户 ID
     * @return 被清除的文档数量
     */
    public int clearIndex(UUID ownerUserId) {
        try {
            int docCount = withUserIndexState(ownerUserId, state -> {
                int count = state.writer.getDocStats().numDocs;
                state.writer.deleteAll();
                state.writer.commit();
                return count;
            });
            log.info("用户 Lucene 索引已清空: ownerUserId={}, 原有文档数={}", ownerUserId, docCount);
            return docCount;
        } catch (Exception e) {
            log.error("清空用户 Lucene 索引失败: ownerUserId={}", ownerUserId, e);
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "清空索引失败");
        }
    }

    /**
     * 清空所有用户的索引内容，用于管理员全量重建前的准备。
     * 遍历磁盘上所有用户索引目录并清除。
     *
     * @return 被清除的文档总数
     */
    public int clearAllIndexes() {
        int totalCleared = 0;
        try {
            // 先关闭并清除所有已缓存的用户索引
            for (Map.Entry<UUID, UserIndexState> entry : userIndexes.asMap().entrySet()) {
                UUID userId = entry.getKey();
                UserIndexState state = entry.getValue();
                synchronized (state) {
                    if (!state.closed) {
                        try {
                            int docCount = state.writer.getDocStats().numDocs;
                            state.writer.deleteAll();
                            state.writer.commit();
                            totalCleared += docCount;
                        } catch (Exception e) {
                            log.warn("清空用户索引失败: ownerUserId={}", userId, e);
                        }
                    }
                }
            }
            userIndexes.invalidateAll();
            userIndexes.cleanUp();

            // 删除磁盘上的所有用户索引目录
            if (Files.exists(basePath) && Files.isDirectory(basePath)) {
                try (var stream = Files.list(basePath)) {
                    for (Path userDir : stream.toList()) {
                        if (Files.isDirectory(userDir)) {
                            try {
                                deleteDirectory(userDir);
                            } catch (IOException e) {
                                log.warn("删除用户索引目录失败: ownerIndexPathHash={}, errorType={}",
                                        Integer.toHexString(userDir.toString().hashCode()),
                                        e.getClass().getSimpleName());
                            }
                        }
                    }
                }
            }
            log.info("全部 Lucene 索引已清空，总文档数: {}", totalCleared);
        } catch (Exception e) {
            log.error("清空全部 Lucene 索引失败", e);
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "清空索引失败");
        }
        return totalCleared;
    }

    /**
     * 递归删除目录及其内容。
     */
    private void deleteDirectory(Path directory) throws IOException {
        if (Files.exists(directory)) {
            try (var stream = Files.walk(directory)) {
                List<Path> paths = stream.sorted((a, b) -> b.compareTo(a)).toList();
                for (Path path : paths) {
                    Files.deleteIfExists(path);
                }
            }
        }
    }

    /**
     * 关闭单个用户的索引资源（Writer 和 Directory）。
     */
    private void closeUserIndex(UserIndexState state) {
        if (state == null) {
            return;
        }
        synchronized (state) {
            if (state.closed) {
                return;
            }
            state.closed = true;
            try {
                if (state.writer.isOpen()) {
                    state.writer.close();
                }
            } catch (IOException e) {
                log.warn("关闭用户索引 writer 失败", e);
            }
            try {
                state.directory.close();
            } catch (IOException e) {
                log.warn("关闭用户索引 directory 失败", e);
            }
        }
    }

    @Override
    public void close() {
        userIndexes.invalidateAll();
        userIndexes.cleanUp();
        analyzer.close();
    }

    int cachedUserIndexCount() {
        userIndexes.cleanUp();
        return userIndexes.asMap().size();
    }

    /**
     * 在单个用户索引状态锁内执行的操作。
     *
     * @param <T> 操作返回类型
     */
    @FunctionalInterface
    private interface UserIndexOperation<T> {
        T execute(UserIndexState state) throws Exception;
    }

    /**
     * 单个用户的 Lucene 索引状态，包含 Directory 和 Writer。
     * Reader 按需创建，不缓存，确保每次读取最新提交的数据。
     */
    private static class UserIndexState {
        final Directory directory;
        final IndexWriter writer;
        boolean closed;

        UserIndexState(Directory directory, IndexWriter writer) {
            this.directory = directory;
            this.writer = writer;
        }
    }
}
