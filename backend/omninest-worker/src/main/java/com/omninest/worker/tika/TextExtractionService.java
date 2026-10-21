package com.omninest.worker.tika;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.service.FileQueryService;
import java.io.IOException;
import java.io.InputStream;
import java.io.Writer;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.tika.exception.TikaException;
import org.apache.tika.extractor.EmbeddedDocumentExtractor;
import org.apache.tika.metadata.Metadata;
import org.apache.tika.parser.AutoDetectParser;
import org.apache.tika.parser.ParseContext;
import org.apache.tika.sax.BodyContentHandler;
import org.apache.tika.sax.ContentHandlerDecorator;
import org.springframework.stereotype.Service;
import org.xml.sax.ContentHandler;
import org.xml.sax.SAXException;

/**
 * 文本提取服务：使用 Apache Tika 从文件内容流解析正文并按块返回。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class TextExtractionService {

    /**
     * 单个 Lucene 文档的最大正文字符数。
     */
    private static final int CHUNK_SIZE_CHARS = 500_000;
    /**
     * 安全护栏：单文件最多索引的块数，对应约 1 亿字符。
     */
    private static final int MAX_CHUNKS = 200;

    private final FileQueryService fileQueryService;

    /**
     * 从受控文件内容流提取文本块。
     *
     * <p>达到块数上限时必须中断解析：只置截断标志会让 Tika 继续把剩余数 GB 的字节流
     * 解完再逐字丢弃，任务墙钟时间与临时对象都按整个文件计费。嵌套文档一律不解析，
     * 否则一个内层归档就能把解析深度和解压字节量放大到不可控。</p>
     *
     * @param ownerUserId 文件所有者
     * @param fileNodeId 文件节点 ID
     * @return 分块提取结果
     */
    public ExtractionResult extract(UUID ownerUserId, UUID fileNodeId) {
        ChunkingTextCollector collector = new ChunkingTextCollector(CHUNK_SIZE_CHARS, MAX_CHUNKS);
        try (FileContentStream contentStream = fileQueryService.openOwnedFileContent(ownerUserId, fileNodeId);
             InputStream inputStream = contentStream.inputStream()) {
            AutoDetectParser parser = new AutoDetectParser();
            ContentHandler handler = new TruncatingContentHandler(new BodyContentHandler(collector), collector);
            Metadata metadata = new Metadata();
            ParseContext context = new ParseContext();
            context.set(EmbeddedDocumentExtractor.class, new SkipEmbeddedDocuments());
            parser.parse(inputStream, handler, metadata, context);
            collector.finish();
        } catch (BusinessException exception) {
            throw exception;
        } catch (SAXException | TikaException | IOException | RuntimeException exception) {
            if (!collector.truncated()) {
                throw new IllegalStateException("文本提取失败: fileNodeId=" + fileNodeId, exception);
            }
            log.info("文本提取按块数上限提前终止解析: fileNodeId={}, maxChunks={}", fileNodeId, MAX_CHUNKS);
        }
        return new ExtractionResult(
                List.copyOf(collector.chunks()),
                collector.textLength(),
                collector.truncated(),
                CHUNK_SIZE_CHARS,
                MAX_CHUNKS
        );
    }

    /**
     * 不解析嵌套文档的抽取器：内层归档与附件不进正文流。
     */
    private static final class SkipEmbeddedDocuments implements EmbeddedDocumentExtractor {

        @Override
        public boolean shouldParseEmbedded(Metadata metadata) {
            return false;
        }

        @Override
        public void parseEmbedded(
                InputStream stream,
                ContentHandler handler,
                Metadata metadata,
                boolean outputHtml
        ) {
            // 刻意不解析嵌套文档，正文只取外层文档
        }
    }

    /**
     * 达到块数上限后抛 {@link SAXException} 终止解析的处理器包装。
     *
     * <p>写入方（{@link Writer}）只能抛 IOException，Tika 会把它当成流读取故障上报；
     * 截断是预期结果，必须走 SAX 的正常终止通道。</p>
     */
    private static final class TruncatingContentHandler extends ContentHandlerDecorator {
        private final ChunkingTextCollector collector;

        TruncatingContentHandler(ContentHandler handler, ChunkingTextCollector collector) {
            super(handler);
            this.collector = collector;
        }

        @Override
        public void characters(char[] ch, int start, int length) throws SAXException {
            super.characters(ch, start, length);
            throwIfTruncated();
        }

        @Override
        public void ignorableWhitespace(char[] ch, int start, int length) throws SAXException {
            super.ignorableWhitespace(ch, start, length);
            throwIfTruncated();
        }

        @Override
        public void endElement(String uri, String localName, String qName) throws SAXException {
            super.endElement(uri, localName, qName);
            throwIfTruncated();
        }

        private void throwIfTruncated() throws SAXException {
            if (collector.truncated()) {
                throw new SAXException("文本提取达到最大分块数，提前结束解析");
            }
        }
    }

    /**
     * 文本提取结果。
     *
     * @param chunks 分块正文
     * @param textLength 正文字符数
     * @param truncated 是否因块数上限截断
     * @param chunkSize 单块字符数
     * @param maxChunks 最大块数
     */
    public record ExtractionResult(
            List<String> chunks,
            int textLength,
            boolean truncated,
            int chunkSize,
            int maxChunks
    ) {
    }

    /**
     * 将 Tika 抽出的正文流式切块，避免把千万字全文同时堆进单个字符串或单条 Lucene 文档。
     */
    static final class ChunkingTextCollector extends Writer {
        private final int chunkSizeChars;
        private final int maxChunks;
        private final List<String> chunks = new ArrayList<>();
        private final StringBuilder buffer;
        private int textLength;
        private boolean truncated;

        ChunkingTextCollector(int chunkSizeChars, int maxChunks) {
            this.chunkSizeChars = chunkSizeChars;
            this.maxChunks = maxChunks;
            this.buffer = new StringBuilder(Math.min(chunkSizeChars, 8192));
        }

        @Override
        public void write(char[] cbuf, int off, int len) {
            if (truncated || len <= 0) {
                return;
            }
            int remaining = len;
            int cursor = off;
            while (remaining > 0 && !truncated) {
                int space = chunkSizeChars - buffer.length();
                int take = Math.min(space, remaining);
                buffer.append(cbuf, cursor, take);
                cursor += take;
                remaining -= take;
                textLength += take;
                if (buffer.length() >= chunkSizeChars) {
                    flushBufferedChunk();
                }
            }
        }

        @Override
        public void flush() {
        }

        @Override
        public void close() {
            finish();
        }

        void finish() {
            if (!truncated && !buffer.isEmpty()) {
                chunks.add(buffer.toString());
                buffer.setLength(0);
            }
        }

        List<String> chunks() {
            return chunks;
        }

        int textLength() {
            return textLength;
        }

        boolean truncated() {
            return truncated;
        }

        private void flushBufferedChunk() {
            if (chunks.size() >= maxChunks) {
                truncated = true;
                buffer.setLength(0);
                log.warn("文本提取达到最大分块数，后续内容不再索引: maxChunks={}", maxChunks);
                return;
            }
            chunks.add(buffer.toString());
            buffer.setLength(0);
        }
    }
}
