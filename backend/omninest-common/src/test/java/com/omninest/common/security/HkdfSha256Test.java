package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HexFormat;
import org.junit.jupiter.api.Test;

/**
 * HKDF-SHA256 派生测试。
 *
 * @author OmniNest
 */
class HkdfSha256Test {

    private static final HexFormat HEX = HexFormat.of();

    @Test
    void derivesRfc5869TestCaseOne() {
        byte[] ikm = new byte[22];
        Arrays.fill(ikm, (byte) 0x0b);

        byte[] okm = HkdfSha256.deriveKey(
                ikm,
                HEX.parseHex("000102030405060708090a0b0c"),
                HEX.parseHex("f0f1f2f3f4f5f6f7f8f9"),
                42
        );

        assertThat(HEX.formatHex(okm)).isEqualTo(
                "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf"
                        + "34007208d5b887185865");
    }

    @Test
    void separatesPurposesWithDistinctInfoLabels() {
        byte[] ikm = "test-secret-at-least-32-bytes-long".getBytes(StandardCharsets.UTF_8);

        byte[] payloadKey = HkdfSha256.deriveKey(
                ikm, HkdfSha256.defaultSalt(), "omninest-payload-hmac-v1", 32);
        byte[] contentKey = HkdfSha256.deriveKey(
                ikm, HkdfSha256.defaultSalt(), "omninest-local-content-token-v1", 32);

        assertThat(contentKey).isNotEqualTo(payloadKey);
    }
}
