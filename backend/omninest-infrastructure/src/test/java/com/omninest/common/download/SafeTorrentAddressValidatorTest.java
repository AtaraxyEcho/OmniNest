package com.omninest.common.download;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
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
