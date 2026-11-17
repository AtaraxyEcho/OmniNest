package com.omninest.modules.reader.dto;

import com.omninest.modules.reader.domain.ReaderAnnotation;
import com.omninest.modules.reader.domain.ReaderBookmark;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.domain.ReaderProgress;
import com.omninest.modules.reader.dto.ReaderDtos.CreateAnnotationRequest;
import com.omninest.modules.reader.dto.ReaderDtos.CreateBookmarkRequest;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateAnnotationRequest;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateItemMetadataRequest;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateProgressRequest;
import jakarta.persistence.Column;
import jakarta.validation.constraints.Size;
import java.lang.reflect.Field;
import java.util.List;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 阅读器请求 DTO 的 {@code @Size(max)} 不得宽于实体列的 {@code @Column(length)}。
 *
 * <p>Bean Validation 先于数据库校验执行：DTO 放行而列宽更窄时，用户输入会在落库阶段
 * 抛 {@code DataIntegrityViolationException}，接口直接 500。实体列宽与数据库基线的
 * 一致性由 {@code JpaBaselineSchemaValidationTest} 负责。</p>
 *
 * @author OmniNest
 */
class ReaderDtoColumnLengthContractTest {

    @Test
    @DisplayName("阅读器请求 DTO 的长度上限不超过实体列宽")
    void requestSizeLimitsMustNotExceedEntityColumnLengths() {
        List<String> violations = List.of(
                verify(CreateAnnotationRequest.class, "highlightText", ReaderAnnotation.class),
                verify(CreateAnnotationRequest.class, "note", ReaderAnnotation.class),
                verify(UpdateAnnotationRequest.class, "note", ReaderAnnotation.class),
                verify(CreateBookmarkRequest.class, "note", ReaderBookmark.class),
                verify(UpdateProgressRequest.class, "readingMode", ReaderProgress.class),
                verify(UpdateItemMetadataRequest.class, "language", ReaderItem.class)
        ).stream().filter(value -> !value.isEmpty()).toList();

        Assertions.assertThat(violations)
                .as("DTO @Size(max) 超过实体列宽时，合法输入会在落库阶段返回 500")
                .isEmpty();
    }

    private static String verify(Class<?> requestType, String fieldName, Class<?> entityType) {
        Size size = field(requestType, fieldName).getAnnotation(Size.class);
        Column column = field(entityType, fieldName).getAnnotation(Column.class);
        if (size == null || column == null) {
            return requestType.getSimpleName() + "." + fieldName + " 缺少 @Size 或 @Column(length)";
        }
        return size.max() <= column.length()
                ? ""
                : requestType.getSimpleName() + "." + fieldName + " max=" + size.max()
                        + " > " + entityType.getSimpleName() + " length=" + column.length();
    }

    private static Field field(Class<?> type, String name) {
        try {
            return type.getDeclaredField(name);
        } catch (NoSuchFieldException exception) {
            throw new AssertionError(type.getSimpleName() + " 缺少字段 " + name, exception);
        }
    }
}
