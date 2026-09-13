package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.reader.config.ReaderArchiveLimitsProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * 阅读文件类型检测工具测试。
 *
 * @author OmniNest
 */
class ReaderFileDetectorTest {

    private ReaderFileDetector detector;

    @BeforeEach
    void setUp() {
        detector = new ReaderFileDetector(new ReaderArchiveSafetyPolicy(new ReaderArchiveLimitsProperties()));
    }

    @Test
    void rejectsUnsupportedComicFormats() {
        assertThat(detector.isReaderFile("comic.cbr")).isFalse();
        assertThat(detector.isReaderFile("comic.cb7")).isFalse();
        assertThat(detector.isReaderFile("comic.cbt")).isFalse();
        assertThat(detector.detectType("comic.cbr")).isNull();
    }

    @Test
    void acceptsSupportedFormats() {
        assertThat(detector.isReaderFile("book.epub")).isTrue();
        assertThat(detector.isReaderFile("book.txt")).isTrue();
        assertThat(detector.isReaderFile("comic.cbz")).isTrue();
        assertThat(detector.isReaderFile("comic.zip")).isTrue();
        assertThat(detector.isReaderFile("manual.pdf")).isTrue();
        assertThat(detector.detectType("manual.pdf")).isEqualTo("PDF");
    }

    @Test
    void detectsContentKindByExtension() {
        assertThat(detector.detectContentKind("CBZ")).isEqualTo("COMIC");
        assertThat(detector.detectContentKind("ZIP")).isEqualTo("COMIC");
        assertThat(detector.detectContentKind("EPUB")).isEqualTo("TEXT");
        assertThat(detector.detectContentKind("TXT")).isEqualTo("TEXT");
        assertThat(detector.detectContentKind("PDF")).isEqualTo("TEXT");
    }
}
