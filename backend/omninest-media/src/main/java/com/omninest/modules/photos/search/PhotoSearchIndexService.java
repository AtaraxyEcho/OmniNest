package com.omninest.modules.photos.search;

import java.io.Closeable;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import org.apache.lucene.analysis.standard.StandardAnalyzer;
import org.apache.lucene.document.Document;
import org.apache.lucene.document.Field;
import org.apache.lucene.document.TextField;
import org.apache.lucene.index.DirectoryReader;
import org.apache.lucene.index.IndexWriter;
import org.apache.lucene.index.IndexWriterConfig;
import org.apache.lucene.index.Term;
import org.apache.lucene.queryparser.classic.QueryParser;
import org.apache.lucene.search.IndexSearcher;
import org.apache.lucene.search.Query;
import org.apache.lucene.search.ScoreDoc;
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
        DirectoryReader newReader = DirectoryReader.openIfChanged(reader);
        if (newReader != null) {
            if (reader != null) {
                reader.close();
            }
            reader = newReader;
        } else if (reader == null) {
            reader = DirectoryReader.open(directory);
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
            doc.add(new TextField(FIELD_PHOTO_ID, photoId.toString(), Field.Store.YES));
            doc.add(new TextField(FIELD_OWNER_USER_ID, ownerUserId.toString(), Field.Store.YES));
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
        } catch (Exception e) {
            log.warn("Lucene 照片索引写入失败: photoId={}", photoId, e);
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
        } catch (Exception e) {
            log.warn("Lucene 照片索引删除失败: photoId={}", photoId, e);
        }
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
            log.warn("Lucene 照片索引批量删除失败: count={}", photoIds.size(), e);
        }
    }

    /**
     * 全文搜索照片，返回按相关性排序的 photoId 列表。
     */
    public List<UUID> search(UUID ownerUserId, String queryStr, int maxResults) {
        List<UUID> results = new ArrayList<>();
        try {
            DirectoryReader r = getReader();
            IndexSearcher searcher = new IndexSearcher(r);
            QueryParser parser = new QueryParser(FIELD_TITLE, analyzer);
            String escaped = QueryParser.escape(queryStr);
            String fullQuery = String.format(
                    "%s:\"%s\" %s:\"%s\" %s:\"%s\" +%s:\"%s\"",
                    FIELD_TITLE, escaped,
                    FIELD_DESCRIPTION, escaped,
                    FIELD_TAGS, escaped,
                    FIELD_OWNER_USER_ID, ownerUserId.toString()
            );
            Query query = parser.parse(fullQuery);
            TopDocs topDocs = searcher.search(query, maxResults);
            for (ScoreDoc scoreDoc : topDocs.scoreDocs) {
                Document doc = searcher.storedFields().document(scoreDoc.doc);
                UUID photoId = UUID.fromString(doc.get(FIELD_PHOTO_ID));
                results.add(photoId);
            }
        } catch (Exception e) {
            log.warn("Lucene 照片搜索失败: queryLength={}, errorType={}",
                    queryStr.length(), e.getClass().getSimpleName());
        }
        return results;
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
