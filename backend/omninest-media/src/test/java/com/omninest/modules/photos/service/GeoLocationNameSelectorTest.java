package com.omninest.modules.photos.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import org.junit.jupiter.api.Test;

/** GeoNames 中文名称选优规则测试。 */
class GeoLocationNameSelectorTest {

    private final GeoLocationNameSelector selector = new GeoLocationNameSelector();

    @Test
    void zhHansPreferredWins() {
        selector.offer(1, "zh", "广州", false, false);
        selector.offer(1, "zh-Hans", "广州市", true, false);
        selector.offer(1, "zh-TW", "廣州市", false, false);
        assertEquals("广州市", selector.best(1));
    }

    @Test
    void zhHansBeatsZh() {
        selector.offer(1, "zh", "杭州", false, false);
        selector.offer(1, "zh-Hans", "杭州市", false, false);
        assertEquals("杭州市", selector.best(1));
    }

    @Test
    void zhHansBeatsZhWithPreferredPerScoringTable() {
        selector.offer(1, "zh", "上海", true, false);
        selector.offer(1, "zh-Hans", "上海市", false, false);
        assertEquals("上海市", selector.best(1));
    }

    @Test
    void zhVariantFallsIntoLowerTier() {
        selector.offer(1, "zh-CN", "广州市", false, false);
        selector.offer(1, "zh", "广州市", false, false);
        assertEquals("广州市", selector.best(1));
    }

    @Test
    void historicIsExcluded() {
        selector.offer(1, "zh-Hans", "旧称", false, true);
        assertNull(selector.best(1));
    }

    @Test
    void preferredBoostsSameTier() {
        selector.offer(1, "zh-Hans", "候选一", false, false);
        selector.offer(1, "zh-Hans", "候选二", true, false);
        assertEquals("候选二", selector.best(1));
    }

    @Test
    void nonChineseLanguageIsRejected() {
        selector.offer(1, "en", "Guangzhou", true, false);
        selector.offer(1, "zha", "壮语名", false, false);
        assertNull(selector.best(1));
    }

    @Test
    void blankNameIsIgnored() {
        selector.offer(1, "zh-Hans", "  ", false, false);
        assertNull(selector.best(1));
    }
}
