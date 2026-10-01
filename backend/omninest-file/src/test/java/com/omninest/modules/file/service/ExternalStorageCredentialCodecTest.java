package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONObject;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * 外部存储凭据安全编解码测试。
 *
 * @author OmniNest
 */
class ExternalStorageCredentialCodecTest {

    @Test
    void editableMetadataExcludesSecretsAndTokens() {
        String credentials = """
                {
                  "provider":"Minio",
                  "access_key_id":"access-id",
                  "secret_access_key":"secret-value",
                  "endpoint":"https://storage.example.com",
                  "region":"cn-east-1"
                }
                """;

        Map<String, String> metadata = ExternalStorageCredentialCodec.extractEditableMetadata("S3", credentials);

        assertThat(metadata).containsEntry("provider", "Minio")
                .containsEntry("access_key_id", "access-id")
                .containsEntry("endpoint", "https://storage.example.com")
                .containsEntry("region", "cn-east-1")
                .doesNotContainKeys("secret_access_key", "token", "client_secret");
    }

    @Test
    void updatePreservesOmittedSecretsAndAppliesMetadataChanges() {
        String existing = """
                {
                  "vendor":"nextcloud",
                  "url":"https://old.example.com/dav",
                  "user":"alice",
                  "pass":"stored-password"
                }
                """;
        String submitted = """
                {
                  "vendor":"nextcloud",
                  "url":"https://new.example.com/dav",
                  "user":"alice",
                  "pass":""
                }
                """;

        JSONObject merged = JSON.parseObject(
                ExternalStorageCredentialCodec.mergeForUpdate("WEBDAV", existing, submitted)
        );

        assertThat(merged.getString("url")).isEqualTo("https://new.example.com/dav");
        assertThat(merged.getString("pass")).isEqualTo("stored-password");
    }

    @Test
    void updatePreservesBlankSensitiveFieldsRegardlessOfCase() {
        String existing = """
                {
                  "PASSWORD":"stored-password"
                }
                """;
        String submitted = """
                {
                  "PASSWORD":""
                }
                """;

        JSONObject merged = JSON.parseObject(
                ExternalStorageCredentialCodec.mergeForUpdate("WEBDAV", existing, submitted)
        );

        assertThat(merged.getString("PASSWORD")).isEqualTo("stored-password");
    }

    @Test
    void sanitizeDropsFieldsOutsideProviderWhitelist() {
        String credentials = """
                {
                  "vendor":"nextcloud",
                  "url":"https://dav.example.com",
                  "user":"alice",
                  "pass":"secret",
                  "type":"s3",
                  "config_is_local":"true"
                }
                """;

        JSONObject sanitized = JSON.parseObject(
                ExternalStorageCredentialCodec.sanitize("WEBDAV", credentials)
        );

        assertThat(sanitized).containsOnlyKeys("vendor", "url", "user", "pass");
    }

    @Test
    void mergeForUpdateDropsFieldsOutsideProviderWhitelist() {
        String existing = """
                {
                  "vendor":"nextcloud",
                  "url":"https://old.example.com",
                  "user":"alice"
                }
                """;
        String submitted = """
                {
                  "url":"https://new.example.com",
                  "type":"s3",
                  "config_is_local":"true"
                }
                """;

        JSONObject merged = JSON.parseObject(
                ExternalStorageCredentialCodec.mergeForUpdate("WEBDAV", existing, submitted)
        );

        assertThat(merged).containsOnlyKeys("vendor", "url", "user");
        assertThat(merged.getString("url")).isEqualTo("https://new.example.com");
    }

    @Test
    void sanitizeKeepsS3FieldsAndDropsWebdavOnlyKeys() {
        String credentials = """
                {
                  "access_key_id":"key",
                  "secret_access_key":"secret",
                  "endpoint":"https://s3.example.com",
                  "region":"us-east-1",
                  "url":"https://should-drop.example.com"
                }
                """;

        JSONObject sanitized = JSON.parseObject(
                ExternalStorageCredentialCodec.sanitize("S3", credentials)
        );

        assertThat(sanitized).containsOnlyKeys("access_key_id", "secret_access_key", "endpoint", "region");
    }
}
