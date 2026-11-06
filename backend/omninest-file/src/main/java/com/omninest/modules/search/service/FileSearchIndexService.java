package com.omninest.modules.search.service;

import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.github.benmanes.caffeine.cache.RemovalListener;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
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
import java.util.concurrent.locks.ReentrantReadWriteLock;
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
import org.apache.lucene.search.SearcherFactory;
import org.apache.lucene.search.SearcherManager;
import org.apache.lucene.search.TermQuery;
import org.apache.lucene.search.TopDocs;
import org.apache.lucene.store.Directory;
import org.apache.lucene.store.NIOFSDirectory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * 文件正文索引服务：按用户隔离的 Lucene 目录，文档键是不可变的 {@code fileObjectId}。
 *
 * <p>索引里只放正文与摘要，不再放文件名、空间类型这些可变元数据——它们以 PostgreSQL
 * 为唯一事实来源，检索时按命中的对象标识实时回表解析。这样重命名、移动目录、复制、
 * 软删除与回收站还原都不会让索引失效：节点标识变了，但它引用的内容对象没变。</p>
 *
 * <p>目录仍按用户物理隔离（个人空间按 {@code ownerUserId} 分目录，共享空间用全零 UUID
 * 目录），既保证租户之间互不可见，也让用户注销时能秒级删盘；如果把全部用户的对象混进
 * 一个目录再按 Top-K 回表过滤，大租户的高频词会把候选名额占满，小租户搜同一词会得到
 * 零结果。</p>
 *
 * <p>正文列 {@code Store.NO} 不可回读，因此同一对象内容只会写一次；需要把内容搬到另一个
 * 目录（跨空间移动、转存自他人共享）时只能重新解析源文件，这条路径由后处理任务负责。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class FileSearchIndexService implements Closeable {
    private static final String FIELD_OBJECT_ID = "objectId";
    private static final String FIELD_CONTENT = "content";
    private static final String FIELD_SNIPPET = "snippet";
    private static final String SPACE_PERSONAL = "PERSONAL";
    private static final String SPACE_SHARED = "SHARED";
    /**
     * 共享空间的全局索引键：共享文件不属于任何个人索引，所有具备浏览权限的成员
     * 都从同一目录检索；个人空间仍按 userId 隔离。
     */
    private static final UUID SHARED_INDEX_KEY = new UUID(0L, 0L);
    private static final int SNIPPET_MAX_CHARS = 200;
    private static final int MAX_SEARCH_TOKENS = 16;
    private static final Duration USER_INDEX_IDLE_TTL = Duration.ofMinutes(30);
    /** 用户删除后的跨进程墓碑后缀：存在时禁止再为该用户创建索引。 */
    private static final String PURGE_MARKER_SUFFIX = ".purge";

    private final Path basePath;
    private final SmartChineseAnalyzer analyzer = new SmartChineseAnalyzer();

    /** 按用户缓存的索引状态，淘汰时同步关闭 Lucene 资源。 */
    private final Cache<UUID, UserIndexState> userIndexes;

    /**
     * 只读检索器缓存：每次搜索都重新打开 DirectoryReader 会在连续输入时反复解析段文件，
     * 这里按索引目录复用 SearcherManager，并在目录删除或缓存淘汰时关闭句柄。
     */
    private final Cache<Path, CachedSearcher> searchers;

    /**
     * 索引生命周期读写锁：检索与增量写入持读锁，全量清空/删盘持写锁。
     * 清空期间若允许并发检索重新打开索引，会读到正在删除的段文件。
     */
    private final ReentrantReadWriteLock lifecycleLock = new ReentrantReadWriteLock();

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
        RemovalListener<Path, CachedSearcher> searcherRemovalListener =
                (path, searcher, cause) -> closeSearcher(searcher);
        this.searchers = Caffeine.<Path, CachedSearcher>newBuilder()
                .maximumSize(Math.max(8, maxCachedUserIndexes + 1))
                .expireAfterAccess(USER_INDEX_IDLE_TTL)
                .executor(Runnable::run)
                .removalListener(searcherRemovalListener)
                .build();
    }

    /**
     * 获取指定索引键对应的目录路径。
     */
    private Path getUserIndexPath(UUID indexKey) {
        return basePath.resolve(indexKey.toString());
    }

    private UUID resolveIndexKey(UUID ownerUserId, String spaceType) {
        return SPACE_SHARED.equals(spaceType) ? SHARED_INDEX_KEY : ownerUserId;
    }

    /**
     * 获取或创建指定用户的索引写入器。
     * 懒加载：首次访问时创建 Directory 和 IndexWriter。
     * 使用 computeIfAbsent 保证线程安全，避免并发创建导致资源泄漏。
     */
    private UserIndexState getUserIndexState(UUID indexKey) throws IOException {
        if (isUserPurged(indexKey)) {
            throw new BusinessException(ErrorCode.FILE_NOT_FOUND, "用户搜索索引已清理");
        }
        try {
            return userIndexes.get(indexKey, id -> {
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

    private <T> T withUserIndexState(UUID indexKey, UserIndexOperation<T> operation) throws Exception {
        lifecycleLock.readLock().lock();
        try {
            while (true) {
                UserIndexState state = getUserIndexState(indexKey);
                synchronized (state) {
                    if (state.closed) {
                        continue;
                    }
                    return operation.execute(state);
                }
            }
        } finally {
            lifecycleLock.readLock().unlock();
        }
    }

    /**
     * 打开指定索引的只读 NRT reader。
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
     * 判断该内容对象在指定索引里是否已有正文文档。
     *
     * <p>同一对象在个人空间被复制成多个节点、或转存后再次保存时，正文不需要重复解析；
     * 调用方据此跳过整轮 Tika 提取。</p>
     *
     * @param ownerUserId 拥有者用户 ID
     * @param spaceType 空间类型（PERSONAL / SHARED）
     * @param fileObjectId 文件对象 ID
     * @return 已有正文文档时返回 true
     */
    public boolean hasObjectContent(UUID ownerUserId, String spaceType, UUID fileObjectId) {
        if (fileObjectId == null) {
            return false;
        }
        UUID indexKey = resolveIndexKey(ownerUserId, spaceType);
        Path indexDir = getUserIndexPath(indexKey);
        lifecycleLock.readLock().lock();
        try {
            // 检索器已缓存说明段文件已打开过，无需再新建 NIOFSDirectory 扫描磁盘。
            if (searchers.getIfPresent(indexDir) == null
                    && (!Files.exists(indexDir) || !indexExists(indexDir))) {
                return false;
            }
            SearcherManager manager = searcherFor(indexDir);
            // 与 searchDirectory 对齐：刚 commit 的文档必须刷新到 NRT reader，
            // 否则去重检查读到旧快照，同一个对象会被整轮重复解析与索引。
            manager.maybeRefresh();
            IndexSearcher searcher = manager.acquire();
            try {
                return searcher.count(new TermQuery(new Term(FIELD_OBJECT_ID, fileObjectId.toString()))) > 0;
            } finally {
                manager.release(searcher);
            }
        } catch (Exception exception) {
            searchers.invalidate(indexDir);
            log.warn("探测已索引正文失败: indexKeyHash={}, errorType={}",
                    Integer.toHexString(indexKey.toString().hashCode()),
                    exception.getClass().getSimpleName());
            return false;
        } finally {
            lifecycleLock.readLock().unlock();
        }
    }

    /**
     * 索引一份文件的完整正文分块。
     *
     * @param fileObjectId 文件对象 ID
     * @param ownerUserId 拥有者用户 ID
     * @param spaceType 空间类型（PERSONAL / SHARED）
     * @param chunks 文本分块，按原文顺序
     */
    public void indexObjectChunks(
            UUID fileObjectId, UUID ownerUserId, String spaceType, List<String> chunks) {
        if (isUserPurged(resolveIndexKey(ownerUserId, spaceType))) {
            return;
        }
        if (chunks == null || chunks.isEmpty()) {
            return;
        }
        UUID indexKey = resolveIndexKey(ownerUserId, spaceType);
        try {
            withUserIndexState(indexKey, state -> {
                state.writer.deleteDocuments(objectTerm(fileObjectId));
                for (String chunk : chunks) {
                    if (chunk == null || chunk.isBlank()) {
                        continue;
                    }
                    state.writer.addDocument(buildDocument(fileObjectId, chunk));
                }
                state.writer.commit();
                return null;
            });
            log.debug("分块索引文件正文: fileObjectId={}, indexKeyHash={}, chunkCount={}",
                    fileObjectId, Integer.toHexString(indexKey.toString().hashCode()), chunks.size());
        } catch (Exception e) {
            throw indexFailure("Lucene 分块索引写入失败: fileObjectId=" + fileObjectId, e);
        }
    }

    /**
     * 删除若干内容对象的正文文档，个人与共享目录一并清理。
     *
     * <p>调用方掌握的是对象标识而不是节点标识：同一对象可能被多个节点引用，
     * 只有对象行被真正回收时才会走到这里。</p>
     *
     * @param fileObjectIds 文件对象 ID 集合
     * @param ownerUserId 拥有者用户 ID
     */
    public void deleteObjects(Collection<UUID> fileObjectIds, UUID ownerUserId) {
        if (fileObjectIds == null || fileObjectIds.isEmpty()) {
            return;
        }
        deleteObjectsFromIndex(fileObjectIds, ownerUserId);
        deleteObjectsFromIndex(fileObjectIds, SHARED_INDEX_KEY);
    }

    private void deleteObjectsFromIndex(Collection<UUID> fileObjectIds, UUID indexKey) {
        // 不存在的索引目录没有可删除文档；跳过可避免为仅删除过的用户创建空目录。
        if (!Files.exists(getUserIndexPath(indexKey))) {
            return;
        }
        try {
            withUserIndexState(indexKey, state -> {
                for (UUID fileObjectId : fileObjectIds) {
                    state.writer.deleteDocuments(objectTerm(fileObjectId));
                }
                state.writer.commit();
                return null;
            });
            log.debug("批量删除正文索引: count={}, indexKeyHash={}",
                    fileObjectIds.size(), Integer.toHexString(indexKey.toString().hashCode()));
        } catch (Exception e) {
            throw indexFailure("Lucene 正文索引批量删除失败: count=" + fileObjectIds.size(), e);
        }
    }

    private static Term objectTerm(UUID fileObjectId) {
        return new Term(FIELD_OBJECT_ID, fileObjectId.toString());
    }

    private Document buildDocument(UUID fileObjectId, String chunk) {
        Document doc = new Document();
        // objectId 用 StringField：TextField 会被分析器按 UUID 连字符切分，
        // deleteDocuments 的精确 Term 永远匹配不到，表现为删除不生效、同一对象重复索引。
        doc.add(new StringField(FIELD_OBJECT_ID, fileObjectId.toString(), Field.Store.YES));
        doc.add(new TextField(FIELD_CONTENT, chunk, Field.Store.NO));
        doc.add(new StoredField(FIELD_SNIPPET, snippetOf(chunk)));
        return doc;
    }

    private String snippetOf(String content) {
        String compact = content.replaceAll("\\s+", " ").trim();
        return compact.length() <= SNIPPET_MAX_CHARS ? compact : compact.substring(0, SNIPPET_MAX_CHARS);
    }

    /**
     * 索引写失败必须向上抛出：消费侧据此重试并进入死信，不能把任务标成成功。
     */
    private IllegalStateException indexFailure(String message, Exception cause) {
        log.error("{}", message, cause);
        return new IllegalStateException(message, cause);
    }

    /**
     * 打开流式分块索引会话：解析每完成一块立即写入，避免整份正文驻留内存。
     *
     * <p>会话期间写入的文档停留在 {@link IndexWriter} 的未提交段缓冲区里，对只读
     * {@link SearcherManager} 不可见；只有 {@link ChunkIndexSession#complete()} 的
     * 唯一一次提交才让「删除旧文档 + 写入全部分块」在同一个 commit point 原子生效。
     * 中途按批提交会把「只解析到前 8 块」的半成品暴露给检索侧，进程被 OOM 杀掉后
     * 残缺分块还会永久留在索引里。</p>
     *
     * <p>会话不是线程安全的，只供单个提取任务顺序调用。</p>
     *
     * @param fileObjectId 文件对象 ID
     * @param ownerUserId 拥有者用户 ID
     * @param spaceType 空间类型
     * @return 分块索引会话
     */
    public ChunkIndexSession openChunkIndex(UUID fileObjectId, UUID ownerUserId, String spaceType) {
        return new ChunkIndexSession(fileObjectId, ownerUserId, spaceType);
    }

    /**
     * 流式分块索引会话，用于文本提取器边解析边写 Lucene。
     */
    public class ChunkIndexSession {
        private final UUID fileObjectId;
        private final UUID ownerUserId;
        private final String spaceType;
        private final UUID indexKey;
        private int totalChunks;
        private boolean reset;

        private ChunkIndexSession(UUID fileObjectId, UUID ownerUserId, String spaceType) {
            this.fileObjectId = fileObjectId;
            this.ownerUserId = ownerUserId;
            this.spaceType = spaceType;
            this.indexKey = resolveIndexKey(ownerUserId, spaceType);
        }

        /**
         * 追加一个正文块并写入索引。
         *
         * @param chunk 正文块
         */
        public void append(String chunk) {
            if (chunk == null || chunk.isBlank() || isUserPurged(indexKey)) {
                return;
            }
            try {
                withUserIndexState(indexKey, state -> {
                    if (!reset) {
                        state.writer.deleteDocuments(objectTerm(fileObjectId));
                        reset = true;
                    }
                    state.writer.addDocument(buildDocument(fileObjectId, chunk));
                    totalChunks++;
                    return null;
                });
            } catch (Exception exception) {
                throw new IllegalStateException("分块索引写入失败: fileObjectId=" + fileObjectId, exception);
            }
        }

        /**
         * 结束会话：提交全部分块。
         *
         * <p>没有任何可提取正文时不写文档——标题检索由数据库按文件名实时完成，
         * 索引里不需要一条只有元数据的空文档。</p>
         *
         * @return 写入的块数
         */
        public int complete() {
            if (isUserPurged(indexKey) || !reset) {
                return totalChunks;
            }
            try {
                withUserIndexState(indexKey, state -> {
                    state.writer.commit();
                    return null;
                });
            } catch (Exception exception) {
                throw new IllegalStateException("分块索引提交失败: fileObjectId=" + fileObjectId, exception);
            }
            log.debug("流式分块索引完成: fileObjectId={}, chunkCount={}, spaceType={}",
                    fileObjectId, totalChunks, spaceType);
            return totalChunks;
        }
    }

    /**
     * 在指定用户的索引中搜索文件正文。
     *
     * @param ownerUserId 拥有者用户 ID
     * @param queryStr    搜索关键词
     * @param maxResults  最大返回数量
     * @return 命中的内容对象与摘要
     */
    public List<FileContentHit> search(UUID ownerUserId, String queryStr, int maxResults) {
        return search(ownerUserId, queryStr, maxResults, null);
    }

    /**
     * 在指定用户的个人索引与共享索引中搜索正文。
     *
     * @param ownerUserId 拥有者用户 ID
     * @param queryStr    搜索关键词
     * @param maxResults  最大返回数量
     * @param spaceType   空间类型过滤（PERSONAL / SHARED / null 表示全部）
     * @return 命中的内容对象与摘要
     */
    public List<FileContentHit> search(UUID ownerUserId, String queryStr, int maxResults, String spaceType) {
        if (queryStr == null || queryStr.isBlank() || maxResults <= 0) {
            return List.of();
        }
        boolean includePersonal = spaceType == null || SPACE_PERSONAL.equals(spaceType);
        boolean includeShared = spaceType == null || SPACE_SHARED.equals(spaceType);
        List<FileContentHit> results = new ArrayList<>();
        if (includePersonal && !isUserPurged(ownerUserId)) {
            results.addAll(searchDirectory(getUserIndexPath(ownerUserId), queryStr, maxResults));
        }
        if (includeShared) {
            results.addAll(searchDirectory(getUserIndexPath(SHARED_INDEX_KEY), queryStr, maxResults));
        }
        results.sort(Comparator.comparingDouble(FileContentHit::score).reversed());
        return results.size() > maxResults ? new ArrayList<>(results.subList(0, maxResults)) : results;
    }

    private List<FileContentHit> searchDirectory(Path indexDir, String queryStr, int maxResults) {
        lifecycleLock.readLock().lock();
        try {
            // 缓存命中时跳过磁盘段文件探测：每次搜索都打开 NIOFSDirectory
            // 会造成冗余的目录遍历与 segments 文件读取。
            if (searchers.getIfPresent(indexDir) == null
                    && (!Files.exists(indexDir) || !indexExists(indexDir))) {
                return List.of();
            }
            SearcherManager manager;
            try {
                manager = searcherFor(indexDir);
            } catch (RuntimeException exception) {
                log.warn("打开索引检索器失败: indexKeyHash={}, errorType={}",
                        Integer.toHexString(indexDir.toString().hashCode()),
                        exception.getClass().getSimpleName());
                return List.of();
            }
            IndexSearcher searcher = null;
            try {
                manager.maybeRefresh();
                searcher = manager.acquire();
                return collectHits(searcher, queryStr, maxResults);
            } catch (Exception exception) {
                // 目录被删除或重建时旧检索器可能失效，丢弃缓存让下一次请求重新打开。
                searchers.invalidate(indexDir);
                log.error("Lucene 搜索失败: indexKeyHash={}, queryLength={}, errorType={}",
                        Integer.toHexString(indexDir.toString().hashCode()), queryStr.length(),
                        exception.getClass().getSimpleName(), exception);
                return List.of();
            } finally {
                if (searcher != null) {
                    try {
                        manager.release(searcher);
                    } catch (IOException exception) {
                        log.warn("释放文件索引 searcher 失败: errorType={}",
                                exception.getClass().getSimpleName());
                    }
                }
            }
        } finally {
            lifecycleLock.readLock().unlock();
        }
    }

    private SearcherManager searcherFor(Path indexDir) {
        CachedSearcher cached = searchers.get(indexDir, path -> {
            try {
                return openSearcher(path);
            } catch (IOException exception) {
                throw new UncheckedIOException(exception);
            }
        });
        return cached.manager();
    }

    private boolean indexExists(Path userDir) {
        try (Directory directory = new NIOFSDirectory(userDir)) {
            return DirectoryReader.indexExists(directory);
        } catch (IOException exception) {
            return false;
        }
    }

    private CachedSearcher openSearcher(Path userDir) throws IOException {
        Directory directory = new NIOFSDirectory(userDir);
        DirectoryReader reader = null;
        try {
            reader = DirectoryReader.open(directory);
            return new CachedSearcher(new SearcherManager(reader, new SearcherFactory()), directory);
        } catch (IOException | RuntimeException exception) {
            if (reader != null) {
                try {
                    reader.close();
                } catch (IOException closeFailure) {
                    exception.addSuppressed(closeFailure);
                }
            }
            try {
                directory.close();
            } catch (IOException closeFailure) {
                exception.addSuppressed(closeFailure);
            }
            throw exception;
        }
    }

    private void closeSearcher(CachedSearcher searcher) {
        if (searcher == null) {
            return;
        }
        try {
            searcher.manager().close();
        } catch (IOException exception) {
            log.warn("关闭文件索引 SearcherManager 失败: errorType={}",
                    exception.getClass().getSimpleName());
        }
        try {
            searcher.directory().close();
        } catch (IOException exception) {
            log.warn("关闭文件索引只读目录失败: errorType={}",
                    exception.getClass().getSimpleName());
        }
    }

    /**
     * 只读检索器与其底层目录；目录需单独关闭，SearcherManager 只负责 reader。
     */
    private record CachedSearcher(SearcherManager manager, Directory directory) {
    }

    private List<FileContentHit> collectHits(
            IndexSearcher searcher,
            String queryStr,
            int maxResults
    ) throws Exception {
        // 每个 token 会生成两个 PrefixQuery；限制去重后的词元数，避免长文本触发
        // Lucene TooManyClauses 与词典重写尖峰。
        List<String> tokens = analyzeTokens(queryStr).stream()
                .distinct()
                .limit(MAX_SEARCH_TOKENS)
                .toList();
        if (tokens.isEmpty()) {
            return List.of();
        }
        BooleanQuery.Builder tokenQuery = new BooleanQuery.Builder();
        for (String token : tokens) {
            tokenQuery.add(buildTokenQuery(token), BooleanClause.Occur.MUST);
        }
        // 超长文件分块后同一对象会命中多条文档，放宽候选后再按对象去重。
        int candidateLimit = Math.max(maxResults * 8, maxResults);
        TopDocs topDocs = searcher.search(tokenQuery.build(), candidateLimit);
        Map<UUID, FileContentHit> bestByObject = new LinkedHashMap<>();
        for (ScoreDoc scoreDoc : topDocs.scoreDocs) {
            Document doc = searcher.storedFields().document(scoreDoc.doc);
            UUID objectId = UUID.fromString(doc.get(FIELD_OBJECT_ID));
            FileContentHit existing = bestByObject.get(objectId);
            if (existing == null || scoreDoc.score > existing.score()) {
                bestByObject.put(objectId, new FileContentHit(
                        objectId,
                        doc.get(FIELD_SNIPPET),
                        scoreDoc.score
                ));
            }
        }
        return new ArrayList<>(bestByObject.values());
    }

    /**
     * 查询词按写入时的分析器切分后逐词组合，任意词元命中正文即可。
     *
     * <p>不能把整段查询包成短语：中文分词后短语要求词元严格相邻，用户输入多个关键词
     * 时常规组合会全部落空。</p>
     */
    private Query buildTokenQuery(String token) {
        Term contentTerm = new Term(FIELD_CONTENT, token);
        return new BooleanQuery.Builder()
                .add(new TermQuery(contentTerm), BooleanClause.Occur.SHOULD)
                .add(new BoostQuery(new PrefixQuery(contentTerm), 0.8f), BooleanClause.Occur.SHOULD)
                .setMinimumNumberShouldMatch(1)
                .build();
    }

    private List<String> analyzeTokens(String queryStr) throws IOException {
        List<String> tokens = new ArrayList<>();
        try (TokenStream stream = analyzer.tokenStream(FIELD_CONTENT, queryStr)) {
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
        // 删盘必须独占：检索或增量写入若在删除窗口重新打开索引，
        // 会读到正在被移除的段文件（NoSuchFileException / AlreadyClosedException）。
        lifecycleLock.writeLock().lock();
        try {
            return deleteUserIndexLocked(ownerUserId);
        } finally {
            lifecycleLock.writeLock().unlock();
        }
    }

    private boolean deleteUserIndexLocked(UUID ownerUserId) {
        // 先立墓碑再删盘：其它进程的索引写入会因墓碑拒绝创建目录，
        // 不再依赖“删盘瞬间恰好没有新 writer”的时序。
        markUserPurged(ownerUserId);
        userIndexes.invalidate(ownerUserId);
        userIndexes.cleanUp();
        searchers.invalidate(getUserIndexPath(ownerUserId));
        searchers.cleanUp();
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
     * 遍历磁盘上所有索引目录并清除。
     *
     * @return 被清除的文档总数
     */
    public int clearAllIndexes() {
        lifecycleLock.writeLock().lock();
        try {
            return clearAllIndexesLocked();
        } finally {
            lifecycleLock.writeLock().unlock();
        }
    }

    private int clearAllIndexesLocked() {
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
            // 先关闭只读句柄再删目录，Windows 上仍被打开的段文件无法删除。
            searchers.invalidateAll();
            searchers.cleanUp();

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
        searchers.invalidateAll();
        searchers.cleanUp();
        analyzer.close();
    }

    int cachedUserIndexCount() {
        userIndexes.cleanUp();
        return userIndexes.asMap().size();
    }

    /**
     * 正文命中的内容对象。
     *
     * @param fileObjectId 文件对象 ID，调用方据此回表解析当前可见节点
     * @param snippet 命中分块的摘要
     * @param score 相关性得分
     */
    public record FileContentHit(UUID fileObjectId, String snippet, float score) {
    }

    /**
     * 在单个索引状态锁内执行的操作。
     *
     * @param <T> 操作返回类型
     */
    @FunctionalInterface
    private interface UserIndexOperation<T> {
        T execute(UserIndexState state) throws Exception;
    }

    /**
     * 单个索引键对应的 Lucene 状态，包含 Directory 和 Writer。
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
