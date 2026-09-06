package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * 三星 SEF trailer 扫描单元测试。
 *
 * @author OmniNest
 */
class PhotoMotionTrailerScannerTest {

    @TempDir
    Path tempDir;

    @Test
    void detectsFooterAtEndOfTailBuffer() {
        byte[] tail = "jpeg-bytes.....SEFT".getBytes(StandardCharsets.US_ASCII);

        assertThat(PhotoMotionTrailerScanner.hasSefTrailer(tail, tail.length)).isTrue();
    }

    @Test
    void ignoresBufferWithoutFooter() {
        byte[] tail = "jpeg-bytes.....SEF_".getBytes(StandardCharsets.US_ASCII);

        assertThat(PhotoMotionTrailerScanner.hasSefTrailer(tail, tail.length)).isFalse();
    }

    @Test
    void respectsValidLengthSmallerThanBuffer() {
        byte[] tail = "xxxxSEFT".getBytes(StandardCharsets.US_ASCII);

        assertThat(PhotoMotionTrailerScanner.hasSefTrailer(tail, 4)).isFalse();
        assertThat(PhotoMotionTrailerScanner.hasSefTrailer(tail, 8)).isTrue();
    }

    @Test
    void scanTailFindsFooterNearEndOfFile() throws IOException {
        Path file = tempDir.resolve("sample.jpg");
        byte[] body = new byte[5000];
        byte[] jpeg = "jpegdata".getBytes(StandardCharsets.US_ASCII);
        System.arraycopy(jpeg, 0, body, 0, jpeg.length);
        byte[] footer = "\u0000\u0000SEFT".getBytes(StandardCharsets.ISO_8859_1);
        Files.write(
                file,
                concat(body, "SEFH-records".getBytes(StandardCharsets.US_ASCII), footer)
        );

        assertThat(PhotoMotionTrailerScanner.scanTail(file)).isTrue();
    }

    @Test
    void scanTailReturnsFalseForPlainJpeg() throws IOException {
        Path file = tempDir.resolve("plain.jpg");
        Files.write(file, "plain-jpeg-content".getBytes(StandardCharsets.US_ASCII));

        assertThat(PhotoMotionTrailerScanner.scanTail(file)).isFalse();
    }

    private byte[] concat(byte[]... parts) {
        int total = 0;
        for (byte[] part : parts) {
            total += part.length;
        }
        byte[] result = new byte[total];
        int offset = 0;
        for (byte[] part : parts) {
            System.arraycopy(part, 0, result, offset, part.length);
            offset += part.length;
        }
        return result;
    }
}
