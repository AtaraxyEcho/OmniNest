package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.config.SecurityProperties;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * HMAC-SHA256 文本负载签名测试。
 *
 * @author OmniNest
 */
class HmacSha256PayloadAuthenticatorTest {

    private final SecurityProperties securityProperties = new SecurityProperties();
    private final PayloadAuthenticator authenticator =
            new HmacSha256PayloadAuthenticator(securityProperties);

    @Test
    void verifyAcceptsMatchingPayloadAndSignature() {
        String signature = authenticator.sign("session-1.1780000000");

        assertThat(authenticator.verify("session-1.1780000000", signature)).isTrue();
    }

    @Test
    void verifyRejectsChangedPayloadOrSignature() {
        String signature = authenticator.sign("session-1.1780000000");

        assertThat(authenticator.verify("session-2.1780000000", signature)).isFalse();
        assertThat(authenticator.verify("session-1.1780000000", signature + "x")).isFalse();
    }

    @Test
    @DisplayName("域分离：签名密钥与 JWT secret 直签结果不同，且跨派生不互相接受")
    void signingKeyIsDerivedAndDistinctFromJwtSecret() throws Exception {
        String payload = "session-1.1780000000";
        String signature = authenticator.sign(payload);

        Mac direct = Mac.getInstance("HmacSHA256");
        direct.init(new SecretKeySpec(
                securityProperties.getJwtSecret().getBytes(StandardCharsets.UTF_8),
                "HmacSHA256"));
        String directSignature = Base64.getUrlEncoder().withoutPadding()
                .encodeToString(direct.doFinal(payload.getBytes(StandardCharsets.UTF_8)));

        assertThat(signature).isNotEqualTo(directSignature);
        // 拿 JWT secret 直签的结果不能通过派生密钥的校验
        assertThat(authenticator.verify(payload, directSignature)).isFalse();
    }
}
