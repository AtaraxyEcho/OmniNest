package com.omninest.common.download;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.download.OfflineDownloadGateway.TaskSnapshot;
import com.omninest.common.json.JsonSupport;
import org.junit.jupiter.api.Test;
import tools.jackson.databind.JsonNode;

/**
 * Aria2RpcClient 返回模型转换测试。
 *
 * @author OmniNest
 */
class Aria2RpcClientTest {

    @Test
    void toTaskSnapshotReturnsTypedStatusAndTorrentName() {
        JsonNode result = JsonSupport.readTree("""
                {
                  "status": "active",
                  "totalLength": "4096",
                  "completedLength": "1024",
                  "downloadSpeed": "512",
                  "files": [
                    {"path": "D:/downloads/movie/video.mkv", "selected": "true"},
                    {"path": "D:/downloads/movie/sample.mkv", "selected": "false"}
                  ],
                  "bittorrent": {"info": {"name": "Example Movie"}}
                }
                """);

        TaskSnapshot snapshot = Aria2RpcClient.toTaskSnapshot(result);

        assertThat(snapshot.state()).isEqualTo("active");
        assertThat(snapshot.totalBytes()).isEqualTo(4096L);
        assertThat(snapshot.completedBytes()).isEqualTo(1024L);
        assertThat(snapshot.speedBytes()).isEqualTo(512L);
        assertThat(snapshot.displayName()).isEqualTo("Example Movie");
        assertThat(snapshot.files()).hasSize(2);
        assertThat(snapshot.files().get(0).selected()).isTrue();
        assertThat(snapshot.files().get(1).selected()).isFalse();
    }

    @Test
    void toTaskSnapshotFallsBackToFirstFileName() {
        JsonNode result = JsonSupport.readTree("""
                {"files": [{"path": "D:/downloads/archive.zip"}]}
                """);

        TaskSnapshot snapshot = Aria2RpcClient.toTaskSnapshot(result);

        assertThat(snapshot.displayName()).isEqualTo("archive.zip");
    }
}
