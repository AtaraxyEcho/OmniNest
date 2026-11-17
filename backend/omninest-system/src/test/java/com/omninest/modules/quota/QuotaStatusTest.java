package com.omninest.modules.quota;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class QuotaStatusTest {

    @Test
    @DisplayName("正常状态：使用量低于预警阈值")
    void resolveNormalWhenBelowWarningThreshold() {
        // 使用 50%，预警 80%
        QuotaStatus status = QuotaStatus.resolve(500, 1000, 80);
        assertThat(status).isEqualTo(QuotaStatus.NORMAL);
    }

    @Test
    @DisplayName("预警状态：使用量达到预警阈值")
    void resolveWarningWhenAtWarningThreshold() {
        // 使用 80%，预警 80%
        QuotaStatus status = QuotaStatus.resolve(800, 1000, 80);
        assertThat(status).isEqualTo(QuotaStatus.WARNING);
    }

    @Test
    @DisplayName("预警状态：使用量在预警和临界之间")
    void resolveWarningBetweenWarningAndCritical() {
        // 使用 90%，预警 80%，临界 95%
        QuotaStatus status = QuotaStatus.resolve(900, 1000, 80);
        assertThat(status).isEqualTo(QuotaStatus.WARNING);
    }

    @Test
    @DisplayName("临界状态：使用量达到 95%")
    void resolveCriticalWhenAt95Percent() {
        QuotaStatus status = QuotaStatus.resolve(950, 1000, 80);
        assertThat(status).isEqualTo(QuotaStatus.CRITICAL);
    }

    @Test
    @DisplayName("临界状态：使用量超过 95%")
    void resolveCriticalWhenAbove95Percent() {
        QuotaStatus status = QuotaStatus.resolve(999, 1000, 80);
        assertThat(status).isEqualTo(QuotaStatus.CRITICAL);
    }

    @Test
    @DisplayName("无限制配额：零配额返回正常")
    void resolveNormalWhenQuotaIsZero() {
        QuotaStatus status = QuotaStatus.resolve(0, 0, 80);
        assertThat(status).isEqualTo(QuotaStatus.NORMAL);
    }

    @Test
    @DisplayName("无限制配额：负数配额返回正常")
    void resolveNormalWhenQuotaIsNegative() {
        QuotaStatus status = QuotaStatus.resolve(100, -1, 80);
        assertThat(status).isEqualTo(QuotaStatus.NORMAL);
    }

    @Test
    @DisplayName("正常状态：使用量为零")
    void resolveNormalWhenUsedIsZero() {
        QuotaStatus status = QuotaStatus.resolve(0, 1000, 80);
        assertThat(status).isEqualTo(QuotaStatus.NORMAL);
    }

    @Test
    @DisplayName("自定义预警阈值：50%")
    void resolveWithCustomWarningThreshold() {
        // 使用 55%，预警 50%
        QuotaStatus status = QuotaStatus.resolve(550, 1000, 50);
        assertThat(status).isEqualTo(QuotaStatus.WARNING);
    }

    @Test
    @DisplayName("枚举值属性")
    void enumValues() {
        assertThat(QuotaStatus.NORMAL.getValue()).isEqualTo("NORMAL");
        assertThat(QuotaStatus.WARNING.getValue()).isEqualTo("WARNING");
        assertThat(QuotaStatus.CRITICAL.getValue()).isEqualTo("CRITICAL");
        assertThat(QuotaStatus.NORMAL.getLabel()).isEqualTo("正常");
    }
}
