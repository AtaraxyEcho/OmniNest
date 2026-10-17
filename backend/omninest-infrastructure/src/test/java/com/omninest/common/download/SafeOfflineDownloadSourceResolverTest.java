package com.omninest.common.download;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SsrfSafeUrlValidator;
import org.junit.jupiter.api.Test;

/**
 * 安全离线下载源解析器测试。
 *
 * @author OmniNest
 */
class SafeOfflineDownloadSourceResolverTest {
    private final OfflineDownloadSourceResolver resolver = new SafeOfflineDownloadSourceResolver(
            new SsrfSafeUrlValidator()
    );

    @Test
    void resolveAcceptsMagnetLinksWithoutDnsLookup() {
        OfflineDownloadSourceResolver.ResolvedSource result =
                resolver.resolve("magnet:?xt=urn:btih:0123456789abcdef");

        assertThat(result.kind()).isEqualTo(OfflineDownloadSourceResolver.SourceKind.MAGNET);
    }

    @Test
    void resolveBlocksLoopbackHttpTargets() {
        assertThatThrownBy(() -> resolver.resolve("http://127.0.0.1:8080/private"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    void resolveBlocksEmbeddedWebSeedTargets() {
        // web seed 会被下载器直接取回内容并落入用户空间，等价于一次带回显的 SSRF。
        assertThatThrownBy(() -> resolver.resolve(
                "magnet:?xt=urn:btih:0123456789abcdef&ws=http%3A%2F%2F127.0.0.1%2Fsecret"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
        assertThatThrownBy(() -> resolver.resolve(
                "magnet:?xt=urn:btih:0123456789abcdef&ws=https%3A%2F%2F169.254.169.254%2Flatest"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    void resolveBlocksLiteralAddressTrackers() {
        assertThatThrownBy(() -> resolver.resolve(
                "magnet:?xt=urn:btih:0123456789abcdef&an=udp%3A%2F%2F127.0.0.1%3A1337%2Fannounce"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
        assertThatThrownBy(() -> resolver.resolve(
                "magnet:?xt=urn:btih:0123456789abcdef&tr=http%3A%2F%2F10.0.0.1%3A80%2Fannounce"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
        assertThatThrownBy(() -> resolver.resolve(
                "magnet:?xt=urn:btih:0123456789abcdef&an=udp%3A%2F%2F%5B%3A%3A1%5D%3A1337%2Fannounce"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    void resolveKeepsHostnameTrackersUnresolved() {
        // tracker 随时可能宕机，把一次名称解析失败变成整条下载链路失败并不合理：
        // .invalid 一定 NXDOMAIN，能通过即证明这里未触发解析。
        OfflineDownloadSourceResolver.ResolvedSource result = resolver.resolve(
                "magnet:?xt=urn:btih:0123456789abcdef&an=udp%3A%2F%2Ftracker.invalid%3A1337%2Fannounce");

        assertThat(result.kind()).isEqualTo(OfflineDownloadSourceResolver.SourceKind.MAGNET);
    }

    @Test
    void resolveRejectsUnparsableMagnetQuery() {
        // %zz 不是合法的百分号转义：URI 层直接拒绝，不进入参数解码，也不放行。
        assertThatThrownBy(() -> resolver.resolve("magnet:?xt=urn:btih:0123456789abcdef&ws=%zz"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("磁力链接格式不正确");
    }
}
