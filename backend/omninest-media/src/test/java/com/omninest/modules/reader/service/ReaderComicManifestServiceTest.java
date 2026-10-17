package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.task.service.TaskRecordService;
import java.lang.reflect.Method;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * 漫画清单生成服务单元测试：覆盖排序键解析和自然排序。
 *
 * <p>目录构建和节点类型推断已迁移至 ComicManifestBuilderTest。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class ReaderComicManifestServiceTest {

    @Mock
    private TaskRecordService taskRecordService;

    @Mock
    private ReaderCoverExtractionService coverExtractionService;

    @InjectMocks
    private ReaderComicManifestService service;

    private Method parseSourceSortKeyMethod;

    @BeforeEach
    void setUp() throws Exception {
        parseSourceSortKeyMethod = ReaderComicManifestService.class
                .getDeclaredMethod("parseSourceSortKey", String.class);
        parseSourceSortKeyMethod.setAccessible(true);

    }

    // ==================== parseSourceSortKey ====================

    @Nested
    @DisplayName("parseSourceSortKey 排序键解析")
    class ParseSourceSortKeyTests {

        @Test
        @DisplayName("Ch001-010.cbz 范围格式 → ch000001")
        void rangeFormat_extractsFirstNumber() throws Exception {
            String result = (String) parseSourceSortKeyMethod.invoke(service, "Ch001-010.cbz");
            assertThat(result).isEqualTo("ch000001");
        }

        @Test
        @DisplayName("Vol.02.zip 卷号格式 → vol000002")
        void volFormat_extractsVolumeNumber() throws Exception {
            String result = (String) parseSourceSortKeyMethod.invoke(service, "Vol.02.zip");
            assertThat(result).isEqualTo("vol000002");
        }

        @Test
        @DisplayName("第003话.cbz 话号格式 → ch000003")
        void chineseChapter_extractsNumber() throws Exception {
            String result = (String) parseSourceSortKeyMethod.invoke(service, "第003话.cbz");
            assertThat(result).isEqualTo("ch000003");
        }

        @Test
        @DisplayName("S01E05.zip 季集格式 → s001e000005")
        void seasonEpisodeFormat_extractsBothNumbers() throws Exception {
            String result = (String) parseSourceSortKeyMethod.invoke(service, "S01E05.zip");
            assertThat(result).isEqualTo("s001e000005");
        }

        @Test
        @DisplayName("random_name.cbz 无数字模式 → 回退为小写文件名")
        void noPattern_fallbackToLowerName() throws Exception {
            String result = (String) parseSourceSortKeyMethod.invoke(service, "random_name.cbz");
            assertThat(result).isEqualTo("random_name");
        }

        @Test
        @DisplayName("null 输入 → 空字符串")
        void nullInput_returnsEmpty() throws Exception {
            String result = (String) parseSourceSortKeyMethod.invoke(service, (Object) null);
            assertThat(result).isEmpty();
        }

        @Test
        @DisplayName("Chapter 005.zip 章节格式 → ch000005")
        void chapterFormat_extractsNumber() throws Exception {
            String result = (String) parseSourceSortKeyMethod.invoke(service, "Chapter 005.zip");
            assertThat(result).isEqualTo("ch000005");
        }

        @Test
        @DisplayName("012.cbz 纯数字前缀 → ch000012")
        void numericPrefix_extractsNumber() throws Exception {
            String result = (String) parseSourceSortKeyMethod.invoke(service, "012.cbz");
            assertThat(result).isEqualTo("ch000012");
        }
    }

    // ==================== applySourceSortMetadata ====================

    @Nested
    @DisplayName("applySourceSortMetadata 季号落库")
    class ApplySourceSortMetadataTests {

        @Test
        @DisplayName("词尾 s+数字 不落季号（Class1 / Windows10）")
        void wordEndingInSFollowedByDigits_doesNotSetSeasonNo() {
            assertThat(apply("Class1 Vol.1.cbz").getSeasonNo()).isNull();
            assertThat(apply("Windows10 第1卷.cbz").getSeasonNo()).isNull();
            assertThat(apply("Class1 Vol.1.cbz").getVolumeNo()).isEqualTo(1);
        }

        @Test
        @DisplayName("带边界的季号照常落库")
        void boundedSeason_setsSeasonNo() {
            assertThat(apply("某动画 S01.cbz").getSeasonNo()).isEqualTo(1);
            assertThat(apply("某动画 第2季.cbz").getSeasonNo()).isEqualTo(2);
        }

        private ReaderItemSource apply(String fileName) {
            ReaderItemSource source = new ReaderItemSource();
            service.applySourceSortMetadata(source, fileName);
            return source;
        }
    }

    // ==================== naturalCompare ====================

    @Nested
    @DisplayName("naturalCompare 自然排序")
    class NaturalCompareTests {

        @Test
        @DisplayName("page2.jpg 在 page10.jpg 之前")
        void numericOrdering_singleDigitsBeforeDouble() {
            int cmp = ReaderComicArchiveParser.naturalCompare("page2.jpg", "page10.jpg");
            assertThat(cmp).isNegative();
        }

        @Test
        @DisplayName("page001.jpg 在 page002.jpg 之前")
        void numericOrdering_paddedNumbers() {
            int cmp = ReaderComicArchiveParser.naturalCompare("page001.jpg", "page002.jpg");
            assertThat(cmp).isNegative();
        }

        @Test
        @DisplayName("相同文件名排序结果为 0")
        void sameName_returnsZero() {
            int cmp = ReaderComicArchiveParser.naturalCompare("page001.jpg", "page001.jpg");
            assertThat(cmp).isZero();
        }

        @Test
        @DisplayName("page10.jpg 在 page2.jpg 之后")
        void reverseOrdering_returnsPositive() {
            int cmp = ReaderComicArchiveParser.naturalCompare("page10.jpg", "page2.jpg");
            assertThat(cmp).isPositive();
        }

        @Test
        @DisplayName("字母部分按字符串比较")
        void alphabeticalOrdering_works() {
            int cmp = ReaderComicArchiveParser.naturalCompare("aaa.jpg", "bbb.jpg");
            assertThat(cmp).isNegative();
        }
    }

}
