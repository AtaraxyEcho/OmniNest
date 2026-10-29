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
}
