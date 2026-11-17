package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileQueryService;
import java.io.BufferedReader;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CoderResult;
import java.nio.charset.Charset;
import java.nio.charset.CharsetDecoder;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * TXT 解码与偏移域的唯一实现。
 *
 * <p>章节清单与按章正文必须由同一套解码规则产出，否则服务端记录的字符偏移
 * 与客户端看到的文本会静默错位。行终止符语义在此固定为：
 * {@code \r\n}、{@code \n}、{@code \r} 一律记 1 个字符，且只有确实读到后继行时才计入，
 * 无终止符的末行不追加；UTF-8 BOM 不参与偏移计数。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class TxtContentDecoder {

    private static final int CHARSET_SAMPLE_BYTES = 64 * 1024;

    /** 全文校验用的字符缓冲大小：固定值，与文件大小无关 */
    private static final int VALIDATION_CHAR_BUFFER = 8 * 1024;

    /** JDK 内置的简体中文超集码表；Dart 侧没有等价实现 */
    private static final Charset GB18030 = Charset.forName("GB18030");

    private final FileQueryService fileQueryService;

    /**
     * 嗅探 TXT 字符集。
     *
     * <p>先认 UTF-8 BOM，再按严格 UTF-8 解码 64 KiB 样本。样本合法不代表整本合法：
     * GB 书的前几十 KB 常有碰巧合法的字节序列，而解码用 REPLACE 策略，误判会把坏序列
     * 变成 {@code U+FFFD} 并永久写进派生文件。因此样本判定为 UTF-8 且文件比样本更长时，
     * 再对全文做一次流式严格校验；校验只增加一次顺序读，不随文件大小申请内存。
     *
     * @param fileNode 源文件描述
     * @return 用于整本解码的字符集
     */
    public Charset detectCharset(FileDescriptor fileNode) {
        byte[] sample = readSample(fileNode);
        if (startsWithUtf8Bom(sample)) {
            return StandardCharsets.UTF_8;
        }
        if (!decodesAsUtf8(sample)) {
            return GB18030;
        }
        if (fileNode.sizeBytes() <= sample.length) {
            return StandardCharsets.UTF_8;
        }
        return validatesAsUtf8(fileNode) ? StandardCharsets.UTF_8 : GB18030;
    }

    private byte[] readSample(FileDescriptor fileNode) {
        byte[] sample = new byte[CHARSET_SAMPLE_BYTES];
        int size = 0;
        try (FileContentStream content = openContent(fileNode)) {
            InputStream input = content.inputStream();
            while (size < sample.length) {
                int read = input.read(sample, size, sample.length - size);
                if (read < 0) {
                    break;
                }
                size += read;
            }
        } catch (IOException exception) {
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "TXT 读取失败");
        }
        return Arrays.copyOf(sample, size);
    }

    private boolean startsWithUtf8Bom(byte[] sample) {
        return sample.length >= 3
                && sample[0] == (byte) 0xEF
                && sample[1] == (byte) 0xBB
                && sample[2] == (byte) 0xBF;
    }

    private boolean decodesAsUtf8(byte[] bytes) {
        CharsetDecoder decoder = strictUtf8Decoder();
        // endOfInput=false：样本按 64 KiB 硬切，末尾常留下半个多字节字符。
        // 直接 decode() 会把它当畸形输入，整本 UTF-8 中文书因此被误判成 GB18030。
        CoderResult result = decoder.decode(
                ByteBuffer.wrap(bytes), CharBuffer.allocate(Math.max(1, bytes.length)), false);
        return !result.isMalformed();
    }

    /**
     * 整本严格解码校验：任何坏序列即判非 UTF-8。
     *
     * <p>坏序列既可能以 {@link CharacterCodingException} 本身抛出，也可能被包装成普通
     * {@code IOException}，两种都要认出；真正的读失败必须让任务失败，
     * 不能悄悄换字符集把内容读成乱码。
     */
    private boolean validatesAsUtf8(FileDescriptor fileNode) {
        char[] buffer = new char[VALIDATION_CHAR_BUFFER];
        long decodedChars = 0L;
        try (FileContentStream content = openContent(fileNode);
             Reader reader = new InputStreamReader(content.inputStream(), strictUtf8Decoder())) {
            int read;
            while ((read = reader.read(buffer)) >= 0) {
                decodedChars += read;
            }
            log.debug("TXT 全文按 UTF-8 校验通过: chars={}", decodedChars);
            return true;
        } catch (IOException exception) {
            if (isCharsetFailure(exception)) {
                log.debug("TXT 全文不是合法 UTF-8，改用 GB18030: failureType={}",
                        exception.getClass().getSimpleName());
                return false;
            }
            throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "TXT 读取失败");
        }
    }

    private boolean isCharsetFailure(IOException exception) {
        return exception instanceof CharacterCodingException
                || exception.getCause() instanceof CharacterCodingException;
    }

    private CharsetDecoder strictUtf8Decoder() {
        return StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT);
    }

    private FileContentStream openContent(FileDescriptor fileNode) {
        return fileQueryService.openOwnedFileContent(fileNode.ownerUserId(), fileNode.id());
    }

    /**
     * 打开行游标。
     *
     * @param fileNode 源文件描述
     * @param charset {@link #detectCharset(FileDescriptor)} 的结果
     * @return 逐行产出解码文本与偏移的游标，调用方必须关闭
     */
    public TxtLineCursor openCursor(FileDescriptor fileNode, Charset charset) {
        FileContentStream content = fileQueryService.openOwnedFileContent(fileNode.ownerUserId(), fileNode.id());
        try {
            CountingInputStream counting = new CountingInputStream(content.inputStream());
            BufferedReader reader = new BufferedReader(new InputStreamReader(counting, charset));
            return new TxtLineCursor(content, counting, reader);
        } catch (RuntimeException exception) {
            closeContent(content);
            throw exception;
        }
    }

    private void closeContent(FileContentStream content) {
        try {
            content.close();
        } catch (IOException exception) {
            log.warn("TXT 内容流清理失败: errorType={}", exception.getClass().getSimpleName());
        }
    }

    /**
     * TXT 行游标：按解码偏移域逐行前进，并暴露已消耗字节数供进度与取消检查。
     */
    public static final class TxtLineCursor implements AutoCloseable {

        private final FileContentStream content;
        private final CountingInputStream counting;
        private final BufferedReader reader;

        private long offset;
        private boolean firstLine = true;

        TxtLineCursor(FileContentStream content, CountingInputStream counting, BufferedReader reader) {
            this.content = content;
            this.counting = counting;
            this.reader = reader;
        }

        /**
         * 读取下一行。
         *
         * @return 行记录；读到文末返回 null
         */
        public TxtLine next() {
            String raw;
            try {
                raw = reader.readLine();
            } catch (IOException exception) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "TXT 读取失败");
            }
            if (raw == null) {
                return null;
            }
            boolean precededBySeparator = !firstLine;
            if (firstLine) {
                if (!raw.isEmpty() && raw.charAt(0) == 0xFEFF) {
                    raw = raw.substring(1);
                }
                firstLine = false;
            } else {
                offset += 1L;
            }
            TxtLine line = new TxtLine(offset, raw, precededBySeparator);
            offset += raw.length();
            return line;
        }

        /**
         * 已消费到的偏移域位置。文末即为整本字符数，某一行之前为该行起始偏移。
         *
         * @return 当前偏移
         */
        public long offset() {
            return offset;
        }

        /**
         * 已消耗字节数，用于按文件大小上报扫描进度。
         *
         * @return 已读字节数
         */
        public long consumedBytes() {
            return counting.consumed();
        }

        @Override
        public void close() {
            try {
                reader.close();
            } catch (IOException exception) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "TXT 读取失败");
            } finally {
                try {
                    content.close();
                } catch (IOException exception) {
                    // 读侧异常已在上方抛出，清理失败只记录类型，不覆盖原始异常
                    log.warn("TXT 内容流关闭失败: errorType={}", exception.getClass().getSimpleName());
                }
            }
        }
    }

    /**
     * 游标产出的一行。
     *
     * @param offset 本行首字符在解码偏移域中的位置
     * @param text 原始行内容，仅剥离首行 BOM，未做首尾空白处理
     * @param precededBySeparator 本行之前是否存在记为 1 字符的行终止符
     */
    public record TxtLine(long offset, String text, boolean precededBySeparator) {
    }

    /**
     * 只统计已消耗字节数的输入流包装。
     */
    private static final class CountingInputStream extends FilterInputStream {

        private long consumed;

        CountingInputStream(InputStream input) {
            super(input);
        }

        long consumed() {
            return consumed;
        }

        @Override
        public int read() throws IOException {
            int value = super.read();
            if (value >= 0) {
                consumed++;
            }
            return value;
        }

        @Override
        public int read(byte[] buffer, int offset, int length) throws IOException {
            int read = super.read(buffer, offset, length);
            if (read > 0) {
                consumed += read;
            }
            return read;
        }
    }
}
