package com.omninest.common.download;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.common.security.SsrfSafeUrlValidator;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

/**
 * 种子内嵌地址校验测试。
 *
 * @author OmniNest
 */
class SafeTorrentAddressValidatorTest {

    private final SafeUrlValidator safeUrlValidator = mock(SafeUrlValidator.class);
    private final SafeTorrentAddressValidator validator = new SafeTorrentAddressValidator(safeUrlValidator);

    @Test
    void checksEmbeddedWebSeedsAndLiteralTrackers() {
        validator.validate(torrent(
                pair("announce", string("udp://10.0.0.1:1337/announce")),
                pair("creation date", "i1700000000e"),
                // info 段与地址无关，必须被完整跳过：里面的 trackers 不参与校验。
                string("info") + "d4:name4:demo8:trackersl" + string("udp://peer.invalid") + "ee",
                pair("url-list", "l" + string("http://seed.invalid/a.bin") + "e")
        ));

        verify(safeUrlValidator).requireSafeHost(URI.create("udp://10.0.0.1:1337/announce"));
        verify(safeUrlValidator).requireSafeHttpUrl("http://seed.invalid/a.bin");
    }

    @Test
    void checksEveryEntryOfNestedAddressLists() {
        validator.validate(torrent(
                pair("announce-list", "ll"
                        + string("udp://192.168.1.10:1337/announce")
                        + string("udp://tracker.invalid:1337/announce")
                        + "ee")
        ));

        verify(safeUrlValidator).requireSafeHost(URI.create("udp://192.168.1.10:1337/announce"));
        verify(safeUrlValidator, never()).requireSafeHost(URI.create("udp://tracker.invalid:1337/announce"));
    }

    @Test
    void leavesHostnameTrackersUnresolved() {
        // tracker 宕机是常态：非字面 IP 不解析，避免把一次解析失败变成整条下载链路的失败。
        validator.validate(torrent(
                pair("announce", string("http://tracker.invalid/announce")),
                pair("announce-list", "l" + "l" + string("udp://tracker.invalid:1337/announce") + "e" + "e")
        ));

        verify(safeUrlValidator, never()).requireSafeHost(any());
        verify(safeUrlValidator, never()).requireSafeHttpUrl(any());
    }

    @Test
    void rejectsMalformedSeeds() {
        assertThatThrownBy(() -> validator.validate(new byte[0]))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("种子文件格式不正确");
        assertThatThrownBy(() -> validator.validate(bytes("not bencode")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("种子文件格式不正确");
        assertThatThrownBy(() -> validator.validate(bytes("d8:announce99:http://1.2.3.4/announcee")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("种子文件格式不正确");
        assertThatThrownBy(() -> validator.validate(bytes("d8:announcee")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("种子文件格式不正确");
    }

    @Test
    void recognizesOnlyRealTorrentStructure() {
        // 展开判定不能靠"能不能解析"：普通下载物里以 d 开头的文本很多，认错就会把一个正常文件当种子重投。
        assertThat(validator.looksLikeTorrent(torrentWithPieces(20))).isTrue();
        assertThat(validator.looksLikeTorrent(torrentWithPieces(40))).isTrue();
        assertThat(validator.looksLikeTorrent(bytes("d4:name4:teste"))).isFalse();
        assertThat(validator.looksLikeTorrent(bytes("d4:infod6:lengthi2ee"))).isFalse();
        assertThat(validator.looksLikeTorrent(torrentWithPieces(19))).isFalse();
        assertThat(validator.looksLikeTorrent(bytes("not bencode"))).isFalse();
        assertThat(validator.looksLikeTorrent(new byte[0])).isFalse();
        assertThat(validator.looksLikeTorrent(null)).isFalse();
    }

    @Test
    void rejectsPrivateWebSeedAndTrackerInRealTorrent() {
        // 上面的用例用 mock 过的 SafeUrlValidator，只证明"字段被读到"；这两条用真实校验器跑真实种子结构，
        // 证明策略本身成立。种子是 aria2 1.36 实际接受并完成的形状（见 docs/2026-10-18/001 §9.6）。
        SafeTorrentAddressValidator real = new SafeTorrentAddressValidator(new SsrfSafeUrlValidator());

        assertThat(real.looksLikeTorrent(base64(PRIVATE_SEED_TORRENT))).isTrue();
        assertThatThrownBy(() -> real.validate(base64(PRIVATE_SEED_TORRENT)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    void webSeedIsHeldToTheFullCheckWhileTrackerHostnameIsNotResolved() {
        SafeTorrentAddressValidator real = new SafeTorrentAddressValidator(new SsrfSafeUrlValidator());

        // web seed 会取回内容，按完整 HTTP 校验：解析不了就拒绝，不放过"域名指向内网"这一类。
        assertThatThrownBy(() -> real.validate(base64(UNRESOLVABLE_WEB_SEED_TORRENT)))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("无法解析");
        // tracker 用 .invalid 域名能通过，正好证明这里未做名称解析（解析失败会被拒）；
        // 代价是"tracker 域名解析到内网"不在代码闸门内，由出网分区兜住（§9.3 实测）。
        assertThat(real.looksLikeTorrent(base64(HOSTNAME_TRACKER_TORRENT))).isTrue();
        real.validate(base64(HOSTNAME_TRACKER_TORRENT));
    }

    @Test
    void ordinaryDownloadBodiesAreNotMistakenForSeeds() {
        // 认错一次的代价是把用户的普通下载物当种子重投，所以负样本必须来自真实文件头。
        assertThat(validator.looksLikeTorrent(base64("ZA=="))).isFalse();
        assertThat(validator.looksLikeTorrent(base64("ZDA6ZQ=="))).isFalse();
        assertThat(validator.looksLikeTorrent(base64("ZDQ6bmFtZTQ6dGVzdGU="))).isFalse();
        // Matroska/WebM 魔数后紧跟的字节可能形成伪 bencode 片段；PNG 头同理。
        assertThat(validator.looksLikeTorrent(base64("GkXfo2Q4OmFubm91bmNlMDpl"))).isFalse();
        assertThat(validator.looksLikeTorrent(base64("iVBORw=="))).isFalse();
    }

    private static final String PRIVATE_SEED_TORRENT =
            "ZDg6YW5ub3VuY2UyOTpodHRwOi8vMTAuMC4wLjE6MTMzNy9hbm5vdW5jZTQ6aW5mb2Q2Omxlbmd0aGk1OGU0Om5hbWUxMDpy"
            + "ZXBvcnQuYmluMTI6cGllY2UgbGVuZ3RoaTEwNDg1NzZlNjpwaWVjZXMyMDpNJBIkwLpyErd1ys+O1eWndvG6qGU4OnVybC1s"
            + "aXN0bDQwOmh0dHA6Ly8xNjkuMjU0LjE2OS4yNTQvbGF0ZXN0L21ldGEtZGF0YS9lZQ==";
    private static final String HOSTNAME_TRACKER_TORRENT =
            "ZDg6YW5ub3VuY2UzOTpodHRwOi8vdHJhY2tlci5leGFtcGxlLmludmFsaWQvYW5ub3VuY2U0OmluZm9kNjpsZW5ndGhpNThl"
            + "NDpuYW1lMTA6cmVwb3J0LmJpbjEyOnBpZWNlIGxlbmd0aGkxMDQ4NTc2ZTY6cGllY2VzMjA6TSQSJMC6chK3dcrPjtXlp3bxu"
            + "qhlZQ==";
    private static final String UNRESOLVABLE_WEB_SEED_TORRENT =
            "ZDQ6aW5mb2Q2Omxlbmd0aGk1OGU0Om5hbWUxMDpyZXBvcnQuYmluMTI6cGllY2UgbGVuZ3RoaTEwNDg1NzZlNjpwaWVjZXMyM"
            + "DpNJBIkwLpyErd1ys+O1eWndvG6qGU4OnVybC1saXN0bDMzOmh0dHA6Ly9zZWVkLmV4YW1wbGUuaW52YWxpZC9hLmJpbmVl";

    private static byte[] base64(String value) {
        return java.util.Base64.getDecoder().decode(value);
    }

    private static byte[] torrentWithPieces(int piecesLength) {
        String pieces = "a".repeat(piecesLength);
        return bytes("d" + string("info") + "d"
                + string("length") + "i2e"
                + string("piece length") + "i2e"
                + string("pieces") + piecesLength + ":" + pieces
                + "ee");
    }

    private static byte[] torrent(String... entries) {
        return bytes("d" + String.join("", entries) + "e");
    }

    private static String pair(String key, String value) {
        return string(key) + value;
    }

    private static String string(String value) {
        return value.length() + ":" + value;
    }

    private static byte[] bytes(String value) {
        return value.getBytes(StandardCharsets.US_ASCII);
    }
}
