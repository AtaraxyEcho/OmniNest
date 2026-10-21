package com.omninest.modules.photos.search;

import java.io.Closeable;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import org.apache.lucene.analysis.TokenStream;
import org.apache.lucene.analysis.standard.StandardAnalyzer;
import org.apache.lucene.analysis.tokenattributes.CharTermAttribute;
import org.apache.lucene.document.Document;
import org.apache.lucene.document.Field;
import org.apache.lucene.document.StringField;
import org.apache.lucene.document.TextField;
import org.apache.lucene.index.DirectoryReader;
import org.apache.lucene.index.IndexWriter;
import org.apache.lucene.index.IndexWriterConfig;
import org.apache.lucene.index.Term;
import org.apache.lucene.store.LockObtainFailedException;
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
 * 照片 Lucene 全文索引服务，支持标题、描述、标签搜索。
 */
@Slf4j
@Service
public class PhotoSearchIndexService implements Closeable {
    private static final String FIELD_PHOTO_ID = "photoId";
    private static final String FIELD_OWNER_USER_ID = "ownerUserId";
    private static final String FIELD_TITLE = "title";
    private static final String FIELD_DESCRIPTION = "description";
    private static final String FIELD_TAGS = "tags";

    private final Path indexPath;
    private final Directory directory;
    private final StandardAnalyzer analyzer = new StandardAnalyzer();
    private volatile IndexWriter writer;
    private volatile DirectoryReader reader;

    public PhotoSearchIndexService(
            @Value("${omninest.search.photo-index-path:${user.home}/.omninest/lucene-photo-index}")
            String indexPath
    ) throws IOException {
        this.indexPath = Path.of(indexPath);
        Files.createDirectories(this.indexPath);
        this.directory = new NIOFSDirectory(this.indexPath);
    }

    private synchronized IndexWriter getWriter() throws IOException {
        if (writer == null || !writer.isOpen()) {
            IndexWriterConfig config = new IndexWriterConfig(analyzer);
            config.setRAMBufferSizeMB(64);
            writer = new IndexWriter(directory, config);
        }
        return writer;
    }

    private synchronized DirectoryReader getReader() throws IOException {
        // 首次读取必须先打开目录：openIfChanged(null) 会直接 NPE，而 search 把异常吞成
        // 空结果，表现为"新进程里照片搜索永远搜不到"。
        if (reader == null) {
            reader = DirectoryReader.open(directory);
            return reader;
        }
        DirectoryReader newReader = DirectoryReader.openIfChanged(reader);
        if (newReader != null) {
            reader.close();
            reader = newReader;
        }
        return reader;
    }

    /**
     * 索引单张照片，已存在则更新。
     */
    public void indexPhoto(UUID photoId, UUID ownerUserId, String title, String description, List<String> tags) {
        try {
            IndexWriter w = getWriter();
            Document doc = new Document();
            // photoId 用 StringField：TextField 会被分析器按 UUID 连字符切分，
            // updateDocument/deleteDocuments 的精确 Term 永远匹配不到，表现为删除不生效、
            // 同一照片重复索引出多份文档。与 FileSearchIndexService 的 fileId 同口径。
            doc.add(new StringField(FIELD_PHOTO_ID, photoId.toString(), Field.Store.YES));
            // 用户 ID 必须不分词：TextField 会被 StandardAnalyzer 按 UUID 连字符切成 5 段，
            // 多租户过滤依赖精确 Term，分词后既脆弱又无法用 FILTER 严格判定。
            doc.add(new StringField(FIELD_OWNER_USER_ID, ownerUserId.toString(), Field.Store.NO));
            doc.add(new TextField(FIELD_TITLE, title != null ? title : "", Field.Store.YES));
            if (description != null && !description.isBlank()) {
                doc.add(new TextField(FIELD_DESCRIPTION, description, Field.Store.YES));
            }
            if (tags != null && !tags.isEmpty()) {
                doc.add(new TextField(FIELD_TAGS, String.join(" ", tags), Field.Store.YES));
            }
            w.updateDocument(new Term(FIELD_PHOTO_ID, photoId.toString()), doc);
            w.commit();
            log.debug("索引照片: photoId={}", photoId);
        } catch (Exception exception) {
            throw indexFailure("写入", photoId, exception);
        }
    }

    /**
     * 删除照片索引。
     */
    public void deletePhoto(UUID photoId) {
        try {
            IndexWriter w = getWriter();
            w.deleteDocuments(new Term(FIELD_PHOTO_ID, photoId.toString()));
            w.commit();
            log.debug("删除照片索引: photoId={}", photoId);
        } catch (Exception exception) {
            throw indexFailure("删除", photoId, exception);
        }
    }

    /**
     * 索引写入失败必须可见：单写进程假设被打破时（卷被其他进程持有 {@code write.lock}）
     * 或磁盘异常时，只留一条 warn 会让搜索静默停留在旧数据，交由消费侧重试并进 DLQ。
     */
    private RuntimeException indexFailure(String action, UUID photoId, Exception exception) {
        if (exception instanceof LockObtainFailedException) {
            log.error("Lucene 索引卷写入锁冲突，照片索引{}失败: photoId={}", action, photoId, exception);
        } else {
            log.error("Lucene 照片索引{}失败: photoId={}", action, photoId, exception);
        }
        return exception instanceof RuntimeException runtimeException
                ? runtimeException
                : new IllegalStateException("照片索引" + action + "失败", exception);
    }

    /**
     * 批量删除照片索引后仅提交一次。
     */
    public void deletePhotos(List<UUID> photoIds) {
        if (photoIds == null || photoIds.isEmpty()) {
            return;
        }
        try {
            IndexWriter w = getWriter();
            for (UUID photoId : photoIds) {
                w.deleteDocuments(new Term(FIELD_PHOTO_ID, photoId.toString()));
            }
            w.commit();
            log.debug("批量删除照片索引: count={}", photoIds.size());
        } catch (Exception e) {
            // 永久删除流程里文档已随业务行消失，搜索侧还会用活动照片二次过滤，
            // 残留文档不会露出；此处只记日志，不让索引失败把清理任务打成 DLQ。
            log.error("Lucene 照片索引批量删除失败: count={}", photoIds.size(), e);
        }
    }

    /**
     * 清空照片索引并返回被丢弃的文档数。
     *
     * <p>索引字段口径变更（例如 {@code ownerUserId} 由分词改为精确项）后，旧文档里的词元
     * 不会再被新查询命中，只能整卷丢弃重投；因此全站重建必须先走这里。仅由单写进程调用。</p>
     *
     * @return 清空前的文档数
     */
    public int clearAll() {
        try {
            IndexWriter w = getWriter();
            int docs = w.getDocStats().numDocs;
            w.deleteAll();
            w.commit();
            log.info("清空照片索引: 丢弃文档数={}, 目录={}", docs, indexPath);
            return docs;
        } catch (Exception e) {
            throw new IllegalStateException("清空照片索引失败", e);
        }
    }

    /**
     * 全文搜索照片，返回按相关性排序的 photoId 列表。
     *
     * <p>查询词必须经同一分词器切分后逐词组合，不能整段包成短语：StandardAnalyzer 把中文
     * 逐字切分，把「北京 旅游」写成短语查询会要求四个字的词元严格相邻，因此永远命不中
     * 「2026北京家庭旅游」这类标题。多租户过滤走 FILTER，不参与打分也不允许退化成加分项。</p>
     */
    public List<UUID> search(UUID ownerUserId, String queryStr, int maxResults) {
        List<UUID> results = new ArrayList<>();
        try {
            DirectoryReader r = getReader();
            IndexSearcher searcher = new IndexSearcher(r);
            List<String> tokens = analyzeTokens(queryStr);
            if (tokens.isEmpty()) {
                return results;
            }
            BooleanQuery.Builder query = new BooleanQuery.Builder()
                    .add(new TermQuery(new Term(FIELD_OWNER_USER_ID, ownerUserId.toString())),
                            BooleanClause.Occur.FILTER);
            for (String token : tokens) {
                query.add(buildTokenQuery(token), BooleanClause.Occur.MUST);
            }
            TopDocs topDocs = searcher.search(query.build(), maxResults);
            for (ScoreDoc scoreDoc : topDocs.scoreDocs) {
                Document doc = searcher.storedFields().document(scoreDoc.doc);
                UUID photoId = UUID.fromString(doc.get(FIELD_PHOTO_ID));
                results.add(photoId);
            }
        } catch (Exception e) {
            // 搜索异常若只记 warn 会表现为"搜不到"，与索引写失败同属必须可见的故障。
            log.error("Lucene 照片搜索失败: queryLength={}, errorType={}",
                    queryStr.length(), e.getClass().getSimpleName(), e);
        }
        return results;
    }

    private Query buildTokenQuery(String token) {
        Term titleTerm = new Term(FIELD_TITLE, token);
        Term descriptionTerm = new Term(FIELD_DESCRIPTION, token);
        Term tagsTerm = new Term(FIELD_TAGS, token);
        return new BooleanQuery.Builder()
                .add(new BoostQuery(new TermQuery(titleTerm), 2.0f), BooleanClause.Occur.SHOULD)
                .add(new BoostQuery(new PrefixQuery(titleTerm), 1.2f), BooleanClause.Occur.SHOULD)
                .add(new TermQuery(descriptionTerm), BooleanClause.Occur.SHOULD)
                .add(new TermQuery(tagsTerm), BooleanClause.Occur.SHOULD)
                .add(new BoostQuery(new PrefixQuery(tagsTerm), 1.1f), BooleanClause.Occur.SHOULD)
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
            stream.end();
        }
        return tokens;
    }

    @Override
    public void close() throws IOException {
        if (writer != null && writer.isOpen()) {
            writer.close();
        }
        if (reader != null) {
            reader.close();
        }
        analyzer.close();
        directory.close();
    }
}
