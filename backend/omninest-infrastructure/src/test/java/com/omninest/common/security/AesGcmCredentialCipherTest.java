package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.config.SecurityProperties;
import com.omninest.common.error.BusinessException;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import org.junit.jupiter.api.Test;

/**
 * 外部凭据加密组件测试。
 *
 * @author OmniNest
 */
class AesGcmCredentialCipherTest {

    @Test
    void encryptUsesRandomIvAndDecryptsAuthenticatedPayload() {
        CredentialCipher cipher = new AesGcmCredentialCipher(properties(1));

        String first = cipher.encrypt("MUSIC_U=secret-cookie");
        String second = cipher.encrypt("MUSIC_U=secret-cookie");

        assertThat(first).doesNotContain("secret-cookie");
        assertThat(second).isNotEqualTo(first);
        assertThat(cipher.decrypt(first)).isEqualTo("MUSIC_U=secret-cookie");
        assertThat(cipher.decrypt(second)).isEqualTo("MUSIC_U=secret-cookie");
    }

    @Test
    void decryptRejectsUnsupportedKeyVersion() {
        CredentialCipher versionOneCipher = new AesGcmCredentialCipher(properties(1));
        CredentialCipher versionTwoCipher = new AesGcmCredentialCipher(properties(2));
        String payload = versionOneCipher.encrypt("cookie=value");

        assertThatThrownBy(() -> versionTwoCipher.decrypt(payload))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("密钥版本");
    }

    @Test
    void decryptAcceptsPreviousKeyVersionAfterRotation() {
        SecurityProperties rotated = properties(2);
        CredentialCipher versionOneCipher = new AesGcmCredentialCipher(properties(1));
        String legacyPayload = versionOneCipher.encrypt("cookie=value");
        rotated.setCredentialEncryptionPreviousKeys(java.util.Map.of(
                1, keyBase64()
        ));

        CredentialCipher rotatedCipher = new AesGcmCredentialCipher(rotated);

        assertThat(rotatedCipher.decrypt(legacyPayload)).isEqualTo("cookie=value");
        assertThat(rotatedCipher.decrypt(rotatedCipher.encrypt("new-secret"))).isEqualTo("new-secret");
    }

    private String keyBase64() {
        byte[] key = "0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.UTF_8);
        return Base64.getEncoder().encodeToString(key);
    }

    private SecurityProperties properties(int version) {
        SecurityProperties properties = new SecurityProperties();
        byte[] key = "0123456789abcdef0123456789abcdef".getBytes(StandardCharsets.UTF_8);
        properties.setCredentialEncryptionKey(Base64.getEncoder().encodeToString(key));
        properties.setCredentialEncryptionKeyVersion(version);
        return properties;
    }
}
