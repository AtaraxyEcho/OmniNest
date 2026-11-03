package com.omninest.common.security;

import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;

/**
 * 内联可执行类型判定。
 *
 * @author OmniNest
 */
class InlineContentPolicyTest {

    @Test
    void treatsMarkupAndScriptTypesAsExecutable() {
        for (String mimeType : new String[]{
                "text/html",
                "application/xhtml+xml",
                "image/svg+xml",
                "application/xml",
                "text/xml",
                "application/javascript",
                "text/javascript"
        }) {
            Assertions.assertThat(InlineContentPolicy.isExecutable(mimeType))
                    .as(mimeType)
                    .isTrue();
        }
    }

    @Test
    void matchesCaseAndSurroundingWhitespace() {
        Assertions.assertThat(InlineContentPolicy.isExecutable("  TEXT/HTML  ")).isTrue();
        Assertions.assertThat(InlineContentPolicy.isExecutable("Image/SVG+XML")).isTrue();
    }

    @Test
    void leavesOrdinaryContentInline() {
        Assertions.assertThat(InlineContentPolicy.isExecutable("video/mp4")).isFalse();
        Assertions.assertThat(InlineContentPolicy.isExecutable("image/png")).isFalse();
        Assertions.assertThat(InlineContentPolicy.isExecutable(null)).isFalse();
        Assertions.assertThat(InlineContentPolicy.isExecutable("   ")).isFalse();
    }

    /**
     * MIME 参数不得绕过判定：签发路径拿到的是带 charset 的完整头。
     */
    @Test
    void stripsMimeTypeParametersBeforeMatching() {
        Assertions.assertThat(InlineContentPolicy.isExecutable("text/html; charset=utf-8")).isTrue();
        Assertions.assertThat(InlineContentPolicy.isExecutable("TEXT/HTML;CHARSET=UTF-8")).isTrue();
        Assertions.assertThat(InlineContentPolicy.isExecutable("image/png;charset=binary")).isFalse();
    }

    /**
     * 任何 {@code +xml} 结构类型都可能内嵌脚本，不能只靠固定清单逐个点名。
     */
    @Test
    void treatsEveryStructuredXmlSuffixAsExecutable() {
        for (String mimeType : new String[]{
                "application/mathml+xml",
                "application/rss+xml",
                "application/atom+xml",
                "application/gpx+xml"
        }) {
            Assertions.assertThat(InlineContentPolicy.isExecutable(mimeType))
                    .as(mimeType)
                    .isTrue();
        }
    }
}
