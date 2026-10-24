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
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import org.apache.lucene.analysis.TokenStream;
import org.apache.lucene.analysis.cn.smart.SmartChineseAnalyzer;
import org.apache.lucene.analysis.tokenattributes.CharTermAttribute;
import org.apache.lucene.document.Document;
import org.apache.lucene.document.Field;
import org.apache.lucene.document.StoredField;
import org.apache.lucene.document.StringField;
import org.apache.lucene.document.TextField;
import org.apache.lucene.index.DirectoryReader;
import org.apache.lucene.index.IndexNotFoundException;
import org.apache.lucene.index.IndexWriter;
import org.apache.lucene.index.IndexWriterConfig;
import org.apache.lucene.index.Term;
import org.apache.lucene.search.BooleanClause;
import org.apache.lucene.search.BooleanQuery;
import org.apache.lucene.search.BoostQuery;
import org.apache.lucene.search.IndexSearcher;
import org.apache.lucene.search.PrefixQuery;
import org.apache.lucene.search.Query;
import org.apache.lucene.search.ScoreDoc;
import org.apache.lucene.search.TermQuery;
import org.apache.lucene.search.TopDocs;
import org.apache.lucene.store.Directory;
import org.apache.lucene.store.NIOFSDirectory;
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
    private static final String FIELD_SNIPPET = "snippet";
    private static final String HAS_CONTENT_YES = "Y";
    private static final String HAS_CONTENT_NO = "N";
    private static final String SPACE_PERSONAL = "PERSONAL";
    private static final String SPACE_SHARED = "SHARED";
    /**
     * 共享空间的全局索引键：共享文件不属于任何个人索引，所有具备浏览权限的成员
     * 都从同一目录检索；个人空间仍按 userId 隔离。
     */
    private static final UUID SHARED_INDEX_KEY = new UUID(0L, 0L);
    private static final int SNIPPET_MAX_CHARS = 200;
    private static final Duration USER_INDEX_IDLE_TTL = Duration.ofMinutes(30);
    /** 用户删除后的跨进程墓碑后缀：存在时禁止再为该用户创建索引。 */
    private static final String PURGE_MARKER_SUFFIX = ".purge";

    private final Path basePath;
    private final SmartChineseAnalyzer analyzer = new SmartChineseAnalyzer();

    /** 按用户缓存的索引状态，淘汰时同步关闭 Lucene 资源。 */
    private final Cache<UUID, UserIndexState> userIndexes;

    /**
     * 创建文件搜索索引服务。
     *
     * @param indexPath 索引根目录
     * @param maxCachedUserIndexes 同时驻留的按用户索引上限
     * @throws IOException 索引根目录创建失败
     */
    public FileSearchIndexService(
            @Value("${omninest.search.index-path:${user.home}/.omninest/lucene-index}") String indexPath,
            @Value("${omninest.search.max-cached-user-indexes:64}") long maxCachedUserIndexes
    ) throws IOException {
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

    private UUID resolveIndexKey(UUID ownerUserId, String spaceType) {
        return SPACE_SHARED.equals(spaceType) ? SHARED_INDEX_KEY : ownerUserId;
    }

    /**
     * 获取或创建指定用户的索引写入器。
     * 懒加载：首次访问时创建 Directory 和 IndexWriter。
     * 使用 computeIfAbsent 保证线程安全，避免并发创建导致资源泄漏。
     */
    private UserIndexState getUserIndexState(UUID userId) throws IOException {
        if (isUserPurged(userId)) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "用户搜索索引已清理");
        }
        try {
            return userIndexes.get(userId, id -> {
                try {
                    Path userPath = getUserIndexPath(id);
                    Files.createDirectories(userPath);
                    // Windows 上 MMapDirectory 在杀软扫描/并发 commit 时易触发 JVM ACCESS_VIOLATION，
                    // 与相册索引一致使用 NIOFSDirectory。
                    Directory directory = new NIOFSDirectory(userPath);
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
     * <p>空间类型必须由调用方显式给出：默认成 PERSONAL 会让共享空间文件在重命名或
     * 恢复后把文档写成个人空间，空间过滤与按空间检索因此失真。</p>
     *
     * @param fileNodeId  文件节点 ID
     * @param ownerUserId 拥有者用户 ID
     * @param title       文件标题
     * @param content     可选的文本内容
     * @param spaceType   空间类型（PERSONAL / SHARED）
     */
    public void indexFile(UUID fileNodeId, UUID ownerUserId, String title, String content, String spaceType) {
        if (isUserPurged(ownerUserId)) {
            return;
        }
        boolean hasContent = content != null && !content.isBlank();
        UUID indexKey = resolveIndexKey(ownerUserId, spaceType);
        try {
            withUserIndexState(indexKey, state -> {
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
                    doc.add(new StoredField(FIELD_SNIPPET, snippetOf(content)));
                }
                // 显式删除后新增，避免 Lucene 软删除使旧文档继续参与搜索。
                state.writer.deleteDocuments(new Term(FIELD_FILE_ID, fileNodeId.toString()));
                state.writer.addDocument(doc);
                state.writer.commit();
                return null;
            });
            // 空间迁移后旧索引目录里的同名文档必须移除，否则个人/共享两条检索路径会同时命中。
            removeFromOtherIndex(fileNodeId, ownerUserId, spaceType);
            log.debug(
                    "索引文件: fileNodeId={}, ownerUserId={}, title={}, spaceType={}",
                    fileNodeId, ownerUserId, title, spaceType
            );
        } catch (Exception e) {
            log.error("Lucene 索引写入失败: fileNodeId={}, ownerUserId={}", fileNodeId, ownerUserId, e);
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
            return hasStoredContent(new IndexSearcher(reader), fileNodeId);
        }
    }

    /**
     * 判断该文件在索引里是否已有正文文档；searcher 为 null 表示索引尚未建立。
     */
    private boolean hasStoredContent(IndexSearcher searcher, UUID fileNodeId) throws IOException {
        if (searcher == null) {
            return false;
        }
        Query query = new BooleanQuery.Builder()
                .add(new TermQuery(new Term(FIELD_FILE_ID, fileNodeId.toString())), BooleanClause.Occur.MUST)
                .add(new TermQuery(new Term(FIELD_HAS_CONTENT, HAS_CONTENT_YES)), BooleanClause.Occur.MUST)
                .build();
        return searcher.count(query) > 0;
    }

    private String snippetOf(String content) {
        String compact = content.replaceAll("\\s+", " ").trim();
        return compact.length() <= SNIPPET_MAX_CHARS ? compact : compact.substring(0, SNIPPET_MAX_CHARS);
    }

    /**
     * 从另一个空间索引中移除同一文件。
     *
     * <p>节点跨空间移动后只会重投当前空间，旧空间的文档不会自动消失；按 fileId
     * 从另一目录一并删除，避免个人与共享检索重复命中同一节点。</p>
     */
    private void removeFromOtherIndex(UUID fileNodeId, UUID ownerUserId, String spaceType) {
        UUID otherKey = SPACE_SHARED.equals(spaceType) ? ownerUserId : SHARED_INDEX_KEY;
        if (!Files.exists(getUserIndexPath(otherKey))) {
            return;
        }
        try {
            withUserIndexState(otherKey, state -> {
                state.writer.deleteDocuments(new Term(FIELD_FILE_ID, fileNodeId.toString()));
                state.writer.commit();
                return null;
            });
        } catch (Exception e) {
            log.warn("清理另一空间索引失败: fileNodeId={}, errorType={}",
                    fileNodeId, e.getClass().getSimpleName());
        }
    }

    /**
     * 删除指定用户的文件索引。
     *
     * @param fileNodeId  文件节点 ID
     * @param ownerUserId 拥有者用户 ID
     */
    public void deleteFile(UUID fileNodeId, UUID ownerUserId) {
        deleteFiles(List.of(fileNodeId), ownerUserId);
    }

    /**
     * 批量删除文件索引，同时清理个人与共享目录。
     *
     * <p>调用方通常只掌握节点所有者，不知道节点当前所在空间；按 fileId 从两个目录
     * 一并删除是幂等的，也能覆盖跨空间移动留下的旧文档。</p>
     *
     * @param fileNodeIds 文件节点 ID 集合
     * @param ownerUserId 拥有者用户 ID
     */
    public void deleteFiles(Collection<UUID> fileNodeIds, UUID ownerUserId) {
        if (fileNodeIds == null || fileNodeIds.isEmpty()) {
            return;
        }
        if (!isUserPurged(ownerUserId)) {
            deleteFilesFromIndex(fileNodeIds, ownerUserId);
        }
        deleteFilesFromIndex(fileNodeIds, SHARED_INDEX_KEY);
    }

    private void deleteFilesFromIndex(Collection<UUID> fileNodeIds, UUID indexKey) {
        // 不存在的索引目录没有可删除文档；跳过可避免为仅删除过的用户创建空目录。
        if (!Files.exists(getUserIndexPath(indexKey))) {
            return;
        }
        try {
            withUserIndexState(indexKey, state -> {
                for (UUID fileNodeId : fileNodeIds) {
                    state.writer.deleteDocuments(new Term(FIELD_FILE_ID, fileNodeId.toString()));
                }
                state.writer.commit();
                return null;
            });
            log.debug("批量删除索引: count={}, indexKey={}", fileNodeIds.size(), indexKey);
        } catch (Exception e) {
            log.error("Lucene 索引批量删除失败: count={}, indexKey={}", fileNodeIds.size(), indexKey, e);
        }
    }

    /**
     * 批量索引文件文档，一次 commit 减少 fsync 次数。
     * 每个条目提供 fileNodeId、title、content 与 spaceType；content 可为 null。
     *
     * <p>与 {@link #indexFile} 同规则：条目不带正文时保留已抽取的正文文档，否则一次目录恢复
     * 就会把可搜索的全文清成只剩标题。
     *
     * @param ownerUserId 拥有者用户 ID
     * @param docs 待索引文档集合
     */
    public void indexFiles(UUID ownerUserId, Collection<IndexDocumentInput> docs) {
        if (docs == null || docs.isEmpty() || isUserPurged(ownerUserId)) {
            return;
        }
        Map<UUID, List<IndexDocumentInput>> docsByIndex = new LinkedHashMap<>();
        for (IndexDocumentInput input : docs) {
            docsByIndex.computeIfAbsent(resolveIndexKey(ownerUserId, input.spaceType()), key -> new ArrayList<>())
                    .add(input);
        }
        for (Map.Entry<UUID, List<IndexDocumentInput>> entry : docsByIndex.entrySet()) {
            UUID indexKey = entry.getKey();
            List<IndexDocumentInput> indexDocs = entry.getValue();
            try {
                withUserIndexState(indexKey, state -> {
                    try (DirectoryReader reader = openReaderOrNull(state)) {
                        IndexSearcher searcher = reader == null ? null : new IndexSearcher(reader);
                        for (IndexDocumentInput input : indexDocs) {
                            boolean hasContent = input.content() != null && !input.content().isBlank();
                            if (!hasContent && hasStoredContent(searcher, input.fileNodeId())) {
                                continue;
                            }
                            Document doc = new Document();
                            doc.add(new StringField(FIELD_FILE_ID, input.fileNodeId().toString(), Field.Store.YES));
                            doc.add(new TextField(FIELD_TITLE, input.title(), Field.Store.YES));
                            doc.add(new StringField(FIELD_SPACE_TYPE, input.spaceType(), Field.Store.YES));
                            doc.add(new StringField(
                                    FIELD_HAS_CONTENT,
                                    hasContent ? HAS_CONTENT_YES : HAS_CONTENT_NO,
                                    Field.Store.YES
                            ));
                            if (hasContent) {
                                doc.add(new TextField(FIELD_CONTENT, input.content(), Field.Store.NO));
                                doc.add(new StoredField(FIELD_SNIPPET, snippetOf(input.content())));
                            }
                            state.writer.deleteDocuments(new Term(FIELD_FILE_ID, input.fileNodeId().toString()));
                            state.writer.addDocument(doc);
                        }
                    }
                    state.writer.commit();
                    return null;
                });
                for (IndexDocumentInput input : indexDocs) {
                    removeFromOtherIndex(input.fileNodeId(), ownerUserId, input.spaceType());
                }
                log.debug("批量索引文件: count={}, indexKey={}", indexDocs.size(), indexKey);
            } catch (Exception e) {
                log.error("Lucene 索引批量写入失败: count={}, indexKey={}", indexDocs.size(), indexKey, e);
            }
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
            UUID ownerUserId, UUID fileNodeId, String title, List<String> chunks, String spaceType) {
        if (isUserPurged(ownerUserId)) {
            return;
        }
        indexFileChunksInternal(ownerUserId, fileNodeId, title, chunks, spaceType);
    }

    private void indexFileChunksInternal(
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
        UUID indexKey = resolveIndexKey(ownerUserId, spaceType);
        try {
            withUserIndexState(indexKey, state -> {
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
                    doc.add(new StoredField(FIELD_SNIPPET, snippetOf(chunk)));
                    state.writer.addDocument(doc);
                }
                state.writer.commit();
                return null;
            });
            removeFromOtherIndex(fileNodeId, ownerUserId, spaceType);
            log.debug(
                    "分块索引文件: fileNodeId={}, ownerUserId={}, chunkCount={}, spaceType={}",
                    fileNodeId, ownerUserId, chunks.size(), spaceType
            );
        } catch (Exception e) {
            log.error("Lucene 分块索引写入失败: fileNodeId={}, ownerUserId={}", fileNodeId, ownerUserId, e);
        }
    }

    /**
     * 打开流式分块索引会话：解析每完成一块立即写入，避免整份正文驻留内存。
     *
     * <p>会话按固定块数分批 commit；首个块写入前清除该文件旧文档，完成时移除另一空间
     * 的残留文档。会话不是线程安全的，只供单个提取任务顺序调用。</p>
     *
     * @param fileNodeId 文件节点 ID
     * @param ownerUserId 拥有者用户 ID
     * @param title 文件标题
     * @param spaceType 空间类型
     * @return 分块索引会话
     */
    public ChunkIndexSession openChunkIndex(
            UUID fileNodeId, UUID ownerUserId, String title, String spaceType) {
        return new ChunkIndexSession(fileNodeId, ownerUserId, title, spaceType);
    }

    /**
     * 流式分块索引会话，用于文本提取器边解析边写 Lucene。
     */
    public class ChunkIndexSession {
        private static final int COMMIT_EVERY_CHUNKS = 8;

        private final UUID fileNodeId;
        private final UUID ownerUserId;
        private final String title;
        private final String spaceType;
        private final UUID indexKey;
        private int pendingChunks;
        private int totalChunks;
        private boolean reset;

        private ChunkIndexSession(UUID fileNodeId, UUID ownerUserId, String title, String spaceType) {
            this.fileNodeId = fileNodeId;
            this.ownerUserId = ownerUserId;
            this.title = title;
            this.spaceType = spaceType;
            this.indexKey = resolveIndexKey(ownerUserId, spaceType);
        }

        /**
         * 追加一个正文块并写入索引。
         *
         * @param chunk 正文块
         */
        public void append(String chunk) {
            if (chunk == null || chunk.isBlank() || isUserPurged(ownerUserId)) {
                return;
            }
            try {
                withUserIndexState(indexKey, state -> {
                    if (!reset) {
                        state.writer.deleteDocuments(new Term(FIELD_FILE_ID, fileNodeId.toString()));
                        reset = true;
                    }
                    Document doc = new Document();
                    doc.add(new StringField(FIELD_FILE_ID, fileNodeId.toString(), Field.Store.YES));
                    doc.add(new TextField(FIELD_TITLE, title, Field.Store.YES));
                    doc.add(new StringField(FIELD_SPACE_TYPE, spaceType, Field.Store.YES));
                    doc.add(new StringField(FIELD_HAS_CONTENT, HAS_CONTENT_YES, Field.Store.YES));
                    doc.add(new TextField(FIELD_CONTENT, chunk, Field.Store.NO));
                    doc.add(new StoredField(FIELD_SNIPPET, snippetOf(chunk)));
                    state.writer.addDocument(doc);
                    totalChunks++;
                    pendingChunks++;
                    if (pendingChunks >= COMMIT_EVERY_CHUNKS) {
                        state.writer.commit();
                        pendingChunks = 0;
                    }
                    return null;
                });
            } catch (Exception exception) {
                throw new IllegalStateException("分块索引写入失败: fileNodeId=" + fileNodeId, exception);
            }
        }

        /**
         * 结束会话：提交剩余文档并清理另一空间索引中的同文件文档。
         *
         * @return 写入的块数
         */
        public int complete() {
            if (isUserPurged(ownerUserId)) {
                return totalChunks;
            }
            if (!reset) {
                // 无可提取正文时仍保留标题元数据文档，沿用一次性索引的语义。
                indexFile(fileNodeId, ownerUserId, title, null, spaceType);
                return totalChunks;
            }
            try {
                withUserIndexState(indexKey, state -> {
                    state.writer.commit();
                    return null;
                });
            } catch (Exception exception) {
                throw new IllegalStateException("分块索引提交失败: fileNodeId=" + fileNodeId, exception);
            }
            removeFromOtherIndex(fileNodeId, ownerUserId, spaceType);
            log.debug("流式分块索引完成: fileNodeId={}, chunkCount={}, spaceType={}",
                    fileNodeId, totalChunks, spaceType);
            return totalChunks;
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
     * 在指定用户的索引中搜索文件（个人与共享空间）。
     *
     * @param ownerUserId 拥有者用户 ID
     * @param queryStr    搜索关键词
     * @param maxResults  最大返回数量
     * @return 搜索结果列表
     */
    public List<SearchResultDto> search(UUID ownerUserId, String queryStr, int maxResults) {
        return search(ownerUserId, queryStr, maxResults, null);
    }

    /**
     * 在指定用户的个人索引与共享索引中搜索文件。
     *
     * @param ownerUserId 拥有者用户 ID
     * @param queryStr    搜索关键词
     * @param maxResults  最大返回数量
     * @param spaceType   空间类型过滤（PERSONAL / SHARED / null 表示全部）
     * @return 搜索结果列表
     */
    public List<SearchResultDto> search(UUID ownerUserId, String queryStr, int maxResults, String spaceType) {
        if (queryStr == null || queryStr.isBlank() || maxResults <= 0 || isUserPurged(ownerUserId)) {
            return new ArrayList<>();
        }
        boolean includePersonal = spaceType == null || SPACE_PERSONAL.equals(spaceType);
        boolean includeShared = spaceType == null || SPACE_SHARED.equals(spaceType);
        List<SearchResultDto> results = new ArrayList<>();
        if (includePersonal) {
            results.addAll(searchDirectory(getUserIndexPath(ownerUserId), queryStr, maxResults, SPACE_PERSONAL));
        }
        if (includeShared) {
            results.addAll(searchDirectory(getUserIndexPath(SHARED_INDEX_KEY), queryStr, maxResults, SPACE_SHARED));
        }
        results.sort(Comparator.comparingDouble(SearchResultDto::score).reversed());
        return results.size() > maxResults ? new ArrayList<>(results.subList(0, maxResults)) : results;
    }

    private List<SearchResultDto> searchDirectory(
            Path userDir, String queryStr, int maxResults, String spaceType) {
        if (!Files.exists(userDir)) {
            return List.of();
        }
        // 搜索一律只读打开索引目录：API 与 Worker 共挂同一 Lucene 卷时，读取路径若构造
        // IndexWriter 就会与 Worker 抢 write.lock，抢锁失败被吞掉后表现为搜索静默返回空结果。
        // Worker 每次写入都 commit，因此 open(directory) 读到的就是最新已提交段。
        try (Directory directory = new NIOFSDirectory(userDir)) {
            if (!DirectoryReader.indexExists(directory)) {
                return List.of();
            }
            try (DirectoryReader reader = DirectoryReader.open(directory)) {
                return collectHits(new IndexSearcher(reader), queryStr, maxResults, spaceType);
            }
        } catch (Exception e) {
            log.error("Lucene 搜索失败: indexKeyHash={}, queryLength={}, errorType={}",
                    Integer.toHexString(userDir.toString().hashCode()), queryStr.length(),
                    e.getClass().getSimpleName(), e);
            return List.of();
        }
    }

    private List<SearchResultDto> collectHits(
            IndexSearcher searcher,
            String queryStr,
            int maxResults,
            String spaceType
    ) throws Exception {
        List<String> tokens = analyzeTokens(queryStr);
        if (tokens.isEmpty()) {
            return List.of();
        }
        BooleanQuery.Builder tokenQuery = new BooleanQuery.Builder();
        for (String token : tokens) {
            tokenQuery.add(buildTokenQuery(token), BooleanClause.Occur.MUST);
        }
        // 空间过滤必须独立成 FILTER 子句；把 spaceType 拼进查询串会因默认 OR 退化成加分项。
        BooleanQuery.Builder query = new BooleanQuery.Builder()
                .add(tokenQuery.build(), BooleanClause.Occur.MUST);
        if (spaceType != null) {
            query.add(new TermQuery(new Term(FIELD_SPACE_TYPE, spaceType)), BooleanClause.Occur.FILTER);
        }
        Query built = query.build();
        // 超长文件分块后同一 fileId 会命中多条文档，放宽候选后再按文件去重。
        int candidateLimit = Math.max(maxResults * 8, maxResults);
        TopDocs topDocs = searcher.search(built, candidateLimit);
        Map<UUID, SearchResultDto> bestByFile = new LinkedHashMap<>();
        for (ScoreDoc scoreDoc : topDocs.scoreDocs) {
            Document doc = searcher.storedFields().document(scoreDoc.doc);
            UUID fileId = UUID.fromString(doc.get(FIELD_FILE_ID));
            SearchResultDto existing = bestByFile.get(fileId);
            if (existing == null || scoreDoc.score > existing.score()) {
                bestByFile.put(fileId, new SearchResultDto(
                        fileId,
                        doc.get(FIELD_TITLE),
                        doc.get(FIELD_SNIPPET),
                        scoreDoc.score
                ));
            }
        }
        return new ArrayList<>(bestByFile.values());
    }

    /**
     * 查询词按写入时的分析器切分后逐词组合，任意字段命中即可。
     *
     * <p>不能把整段查询包成短语：中文分词后短语要求词元严格相邻，用户输入多个关键词
     * 时常规组合会全部落空。标题词项加权，正文前缀命中给较低权重。</p>
     */
    private Query buildTokenQuery(String token) {
        Term titleTerm = new Term(FIELD_TITLE, token);
        Term contentTerm = new Term(FIELD_CONTENT, token);
        return new BooleanQuery.Builder()
                .add(new BoostQuery(new TermQuery(titleTerm), 2.0f), BooleanClause.Occur.SHOULD)
                .add(new BoostQuery(new PrefixQuery(titleTerm), 1.2f), BooleanClause.Occur.SHOULD)
                .add(new TermQuery(contentTerm), BooleanClause.Occur.SHOULD)
                .add(new BoostQuery(new PrefixQuery(contentTerm), 0.8f), BooleanClause.Occur.SHOULD)
                .setMinimumNumberShouldMatch(1)
                .build();
    }

    private List<String> analyzeTokens(String queryStr) throws IOException {
        List<String> tokens = new ArrayList<>();
        try (TokenStream stream = analyzer.tokenStream(FIELD_TITLE, queryStr)) {
            CharTermAttribute term = stream.addAttribute(CharTermAttribute.class);
            stream.reset();
            while (stream.incrementToken()) {
                tokens.add(term.toString());
            }
        }
        return tokens;
    }

    /**
     * 仅关闭并移除本进程缓存的用户索引，不触碰磁盘目录。
     *
     * <p>用户删除时请求进程先释放自己的 writer，目录物理删除由 Worker 执行；
     * 两个进程都持有 writer 时，Windows 上后删的一方会因写锁失败。</p>
     *
     * @param ownerUserId 用户 ID
     */
    public void evictUserIndex(UUID ownerUserId) {
        userIndexes.invalidate(ownerUserId);
        userIndexes.cleanUp();
    }

    /**
     * 为用户索引立跨进程墓碑：存在墓碑时任何进程都不得再创建该用户索引。
     *
     * <p>墓碑在索引根目录下、与用户目录同级，API 与 Worker 共挂同一卷，
     * 因此不依赖进程内状态或删除时序。用户 ID 不会被复用，墓碑保留到
     * 管理员全量重建（{@link #clearAllIndexes()}）时统一清除。</p>
     *
     * @param ownerUserId 用户 ID
     */
    public void markUserPurged(UUID ownerUserId) {
        if (ownerUserId == null) {
            return;
        }
        try {
            Files.createDirectories(basePath);
            Files.createFile(purgeMarkerPath(ownerUserId));
        } catch (FileAlreadyExistsException ignored) {
            // 幂等：Worker 重试或 API 与 Worker 先后写入同一墓碑。
        } catch (IOException exception) {
            log.warn("写入用户索引清理标记失败: indexKeyHash={}, errorType={}",
                    Integer.toHexString(ownerUserId.toString().hashCode()),
                    exception.getClass().getSimpleName());
        }
        evictUserIndex(ownerUserId);
    }

    /**
     * 用户索引是否已被墓碑封禁。
     *
     * @param ownerUserId 用户 ID
     * @return 已写入清理墓碑时返回 true
     */
    public boolean isUserPurged(UUID ownerUserId) {
        return ownerUserId != null && Files.exists(purgeMarkerPath(ownerUserId));
    }

    private Path purgeMarkerPath(UUID ownerUserId) {
        return basePath.resolve(ownerUserId + PURGE_MARKER_SUFFIX);
    }

    /**
     * 删除指定用户的索引目录与缓存，用于用户物理删除后的空间回收。
     *
     * <p>先立墓碑再关闭缓存 writer 并删目录：墓碑阻止其它进程在删盘期间
     * 重新创建该用户索引；删除成功后墓碑保留，直到管理员全量重建。</p>
     *
     * @param ownerUserId 用户 ID
     * @return 目录已删除或原本不存在时返回 true；删除失败返回 false
     */
    public boolean deleteUserIndex(UUID ownerUserId) {
        // 先立墓碑再删盘：其它进程的索引写入会因墓碑拒绝创建目录，
        // 不再依赖“删盘瞬间恰好没有新 writer”的时序。
        markUserPurged(ownerUserId);
        userIndexes.invalidate(ownerUserId);
        userIndexes.cleanUp();
        try {
            deleteDirectory(getUserIndexPath(ownerUserId));
            log.info("已删除用户搜索索引目录: indexKeyHash={}",
                    Integer.toHexString(ownerUserId.toString().hashCode()));
            return true;
        } catch (IOException e) {
            log.warn("删除用户搜索索引目录失败: indexKeyHash={}, errorType={}",
                    Integer.toHexString(ownerUserId.toString().hashCode()),
                    e.getClass().getSimpleName());
            return false;
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
        if (isUserPurged(ownerUserId)) {
            return 0;
        }
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
                        } else if (userDir.getFileName().toString().endsWith(PURGE_MARKER_SUFFIX)) {
                            Files.deleteIfExists(userDir);
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
