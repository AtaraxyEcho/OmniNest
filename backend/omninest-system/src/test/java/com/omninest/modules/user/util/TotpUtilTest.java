package com.omninest.modules.user.util;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import org.junit.jupiter.api.Test;

/**
 * RFC 6238 TOTP 工具测试，含官方附录 B 测试向量（取 8 位结果的末 6 位）。
 *
 * @author OmniNest
 */
class TotpUtilTest {

    /** RFC 6238 附录 B 标准秘钥 "12345678901234567890" 的 Base32 编码。 */
    private static final String RFC_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";

    @Test
    void matchesRfc6238AppendixBVectors() {
        assertThat(TotpUtil.currentCode(RFC_SECRET, Instant.ofEpochSecond(59))).isEqualTo("287082");
        assertThat(TotpUtil.currentCode(RFC_SECRET, Instant.ofEpochSecond(1111111109))).isEqualTo("081804");
        assertThat(TotpUtil.currentCode(RFC_SECRET, Instant.ofEpochSecond(1111111111))).isEqualTo("050471");
        assertThat(TotpUtil.currentCode(RFC_SECRET, Instant.ofEpochSecond(1234567890))).isEqualTo("005924");
        assertThat(TotpUtil.currentCode(RFC_SECRET, Instant.ofEpochSecond(2000000000))).isEqualTo("279037");
        assertThat(TotpUtil.currentCode(RFC_SECRET, Instant.ofEpochSecond(20000000000L))).isEqualTo("353130");
    }

    @Test
    void matchingStepAcceptsWindowAndReportsStep() {
        long step = TotpUtil.matchingStep(
                RFC_SECRET, "287082", Instant.ofEpochSecond(59), TotpUtil.DEFAULT_SKEW, Long.MIN_VALUE);
        assertThat(step).isEqualTo(1L);
    }

    @Test
    void matchingStepRejectsReplayOfUsedStep() {
        assertThat(TotpUtil.matchingStep(
                RFC_SECRET, "287082", Instant.ofEpochSecond(59), TotpUtil.DEFAULT_SKEW, 1L))
                .isEqualTo(TotpUtil.NO_MATCH);
    }

    @Test
    void matchingStepRejectsMalformedCodes() {
        Instant at = Instant.ofEpochSecond(59);
        assertThat(TotpUtil.matchingStep(RFC_SECRET, "28708", at, 1, Long.MIN_VALUE)).isEqualTo(TotpUtil.NO_MATCH);
        assertThat(TotpUtil.matchingStep(RFC_SECRET, "28708a", at, 1, Long.MIN_VALUE)).isEqualTo(TotpUtil.NO_MATCH);
        assertThat(TotpUtil.matchingStep(RFC_SECRET, null, at, 1, Long.MIN_VALUE)).isEqualTo(TotpUtil.NO_MATCH);
        assertThat(TotpUtil.matchingStep("", "287082", at, 1, Long.MIN_VALUE)).isEqualTo(TotpUtil.NO_MATCH);
    }

    @Test
    void matchingStepRejectsCodeOutsideWindow() {
        Instant now = Instant.now();
        String futureCode = TotpUtil.currentCode(RFC_SECRET, now.plusSeconds(600));
        assertThat(TotpUtil.matchingStep(RFC_SECRET, futureCode, now, TotpUtil.DEFAULT_SKEW, Long.MIN_VALUE))
                .isEqualTo(TotpUtil.NO_MATCH);
    }

    @Test
    void base32RoundTripsAndToleratesVariants() {
        byte[] bytes = {(byte) 0xFF, 0x00, (byte) 0xAB, 0x11, 0x7F, 0x33};
        String encoded = TotpUtil.base32Encode(bytes);
        assertThat(TotpUtil.base32Decode(encoded)).isEqualTo(bytes);
        assertThat(TotpUtil.base32Decode(encoded.toLowerCase(java.util.Locale.ROOT))).isEqualTo(bytes);
        assertThat(TotpUtil.base32Decode(encoded + "====")).isEqualTo(bytes);
        assertThat(TotpUtil.base32Decode(encoded + " ")).isEqualTo(bytes);
        assertThat(TotpUtil.base32Decode(encoded + "1!")).isEmpty();
    }

    @Test
    void generateSecretIsThirtyTwoCharsAndUnique() {
        String first = TotpUtil.generateSecret();
        String second = TotpUtil.generateSecret();
        assertThat(first).hasSize(32).matches("[A-Z2-7]+");
        assertThat(first).isNotEqualTo(second);
        assertThat(TotpUtil.currentCode(first, Instant.now())).matches("\\d{6}");
    }

    @Test
    void otpauthUriCarriesIssuerAccountAndSecret() {
        String uri = TotpUtil.otpauthUri("OmniNest", "admin user", RFC_SECRET);
        assertThat(uri)
                .startsWith("otpauth://totp/")
                .contains("secret=" + RFC_SECRET)
                .contains("issuer=OmniNest")
                .contains("algorithm=SHA1")
                .contains("digits=6")
                .contains("period=30")
                .contains("admin%20user");
    }
}
