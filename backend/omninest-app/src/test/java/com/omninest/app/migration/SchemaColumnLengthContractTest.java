package com.omninest.app.migration;

import com.omninest.modules.reader.domain.ReaderAnnotation;
import com.omninest.modules.reader.domain.ReaderBookmark;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.search.domain.SearchIndexState;
import jakarta.persistence.Column;
import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.Field;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 阅读器实体列宽与 V001 基线的静态契约（不依赖 Docker，可在普通单测阶段执行）。
 *
 * <p>{@code JpaBaselineSchemaValidationTest} 的 Hibernate {@code validate} 只校验列存在与
 * 类型族，不校验 {@code varchar} 长度；缺少 Docker 时该用例还会被跳过。这里直接解析
 * 基线 SQL，锁死 DTO/实体最容易与列宽漂移的阅读器字段。</p>
 *
 * @author OmniNest
 */
class SchemaColumnLengthContractTest {

    private static final Pattern CREATE_TABLE = Pattern.compile(
            "CREATE TABLE \"omni\"\\.\"([^\"]+)\" \\((.*?)\\n\\)\\s*;",
            Pattern.DOTALL);
    private static final Pattern VARCHAR_COLUMN = Pattern.compile("\"([^\"]+)\" varchar\\((\\d+)\\)");

    @Test
    @DisplayName("阅读器实体 @Column(length) 与 V001 列宽严格一致")
    void readerEntityLengthsMatchBaseline() throws IOException {
        Map<String, Integer> columnLengths = loadBaselineLengths();
        assertLength(columnLengths, "reader_annotations", "highlight_text",
                ReaderAnnotation.class, "highlightText");
        assertLength(columnLengths, "reader_annotations", "note",
                ReaderAnnotation.class, "note");
        assertLength(columnLengths, "reader_bookmarks", "note",
                ReaderBookmark.class, "note");
        assertLength(columnLengths, "reader_items", "language",
                ReaderItem.class, "language");
        assertLength(columnLengths, "reader_items", "item_type",
                ReaderItem.class, "itemType");
        assertLength(columnLengths, "reader_progress", "reading_mode",
                ReaderProgress.class, "readingMode");
    }

    @Test
    @DisplayName("搜索索引状态实体列宽与 V001 基线严格一致")
    void searchEntityLengthsMatchBaseline() throws IOException {
        Map<String, Integer> columnLengths = loadBaselineLengths();
        // dictionary_version 没有显式 length 时 Hibernate 按 255 建模，比列宽 80 更宽：
        // 校验模式不会报错，但超长的词典版本串会在写入时被数据库截断或拒绝。
        assertLength(columnLengths, "search_index_states", "dictionary_version",
                SearchIndexState.class, "dictionaryVersion");
        assertLength(columnLengths, "search_index_states", "analyzer_name",
                SearchIndexState.class, "analyzerName");
    }

    private static void assertLength(
            Map<String, Integer> columnLengths,
            String table,
            String column,
            Class<?> entityType,
            String fieldName
    ) {
        Integer baseline = columnLengths.get(table + "." + column);
        Assertions.assertThat(baseline).as(table + "." + column + " 未在 V001 中定义").isNotNull();
        Field field;
        try {
            field = entityType.getDeclaredField(fieldName);
        } catch (NoSuchFieldException exception) {
            throw new AssertionError(entityType.getSimpleName() + " 缺少字段 " + fieldName, exception);
        }
        Column annotation = field.getAnnotation(Column.class);
        Assertions.assertThat(annotation).as(entityType.getSimpleName() + "." + fieldName + " 缺少 @Column").isNotNull();
        Assertions.assertThat(annotation.length())
                .as(entityType.getSimpleName() + "." + fieldName + " 与 " + table + "." + column
                        + " 列宽不一致")
                .isEqualTo(baseline);
    }

    private static Map<String, Integer> loadBaselineLengths() throws IOException {
        String sql;
        try (InputStream input = SchemaColumnLengthContractTest.class
                .getResourceAsStream("/db/migration/V001__init_schema.sql")) {
            Assertions.assertThat(input).as("V001 基线必须存在于测试类路径").isNotNull();
            sql = new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }
        Map<String, Integer> lengths = new HashMap<>();
        Matcher tableMatcher = CREATE_TABLE.matcher(sql);
        while (tableMatcher.find()) {
            String table = tableMatcher.group(1);
            Matcher columnMatcher = VARCHAR_COLUMN.matcher(tableMatcher.group(2));
            while (columnMatcher.find()) {
                lengths.put(table + "." + columnMatcher.group(1), Integer.parseInt(columnMatcher.group(2)));
            }
        }
        return lengths;
    }
}
