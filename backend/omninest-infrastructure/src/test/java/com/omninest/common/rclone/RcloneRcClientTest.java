package com.omninest.common.rclone;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.json.JsonSupport;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;

/**
 * RcloneRcClient 返回模型转换测试。
 *
 * @author OmniNest
 */
class RcloneRcClientTest {

    @Test
    void parseDirectoryEntriesReturnsTypedValuesAndPlainMetadata() {
        JsonNode result = JsonSupport.readTree("""
                {"list": [{
                  "Name": "report.pdf",
                  "Path": "documents/report.pdf",
                  "IsDir": false,
                  "Size": 2048,
                  "ModTime": "2026-07-22T08:30:00Z",
                  "MimeType": "application/pdf",
                  "Hash": "abc123",
                  "Checksums": {"sha1": "abc123"},
                  "Tags": ["document"]
                }]}
                """);

        List<RcloneGateway.DirectoryEntry> entries = RcloneRcClient.parseDirectoryEntries(result);

        assertThat(entries).singleElement().satisfies(entry -> {
            assertThat(entry.name()).isEqualTo("report.pdf");
            assertThat(entry.path()).isEqualTo("documents/report.pdf");
            assertThat(entry.directory()).isFalse();
            assertThat(entry.sizeBytes()).isEqualTo(2048L);
            assertThat(entry.modifiedAt()).isEqualTo(Instant.parse("2026-07-22T08:30:00Z"));
            assertThat(entry.mimeType()).isEqualTo("application/pdf");
            assertThat(entry.hash()).isEqualTo("abc123");
            assertThat(entry.metadata().get("Checksums")).isInstanceOf(Map.class);
            assertThat(entry.metadata().get("Tags")).isInstanceOf(List.class);
            assertThat(entry.metadata().values())
                    .noneMatch(value -> value instanceof JsonNode);
        });
    }

    @Test
    void parseDirectoryEntriesIgnoresInvalidModificationTime() {
        JsonNode result = JsonSupport.readTree("""
                {"list": [{"Name": "legacy.txt", "ModTime": "not-an-instant"}]}
                """);

        List<RcloneGateway.DirectoryEntry> entries = RcloneRcClient.parseDirectoryEntries(result);

        assertThat(entries).singleElement().extracting(RcloneGateway.DirectoryEntry::modifiedAt).isNull();
    }
}
