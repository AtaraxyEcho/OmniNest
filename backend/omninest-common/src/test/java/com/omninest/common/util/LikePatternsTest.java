package com.omninest.common.util;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * LIKE 模式串转义测试。
 *
 * @author OmniNest
 */
class LikePatternsTest {

    @Test
    void escapesWildcardsAndTheEscapeCharacterItself() {
        assertThat(LikePatterns.escapeSpecials("100% drift")).isEqualTo("100\\% drift");
        assertThat(LikePatterns.escapeSpecials("now_ here")).isEqualTo("now\\_ here");
        assertThat(LikePatterns.escapeSpecials("back\\slash")).isEqualTo("back\\\\slash");
    }

    @Test
    void leavesPlainTextUnchanged() {
        assertThat(LikePatterns.escapeSpecials("northern drift")).isEqualTo("northern drift");
    }
}
