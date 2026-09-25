package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

import com.omninest.common.error.BusinessException;
import java.net.InetAddress;
import java.net.UnknownHostException;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * SSRF 防护验证器测试。
 * 覆盖 IPv4/IPv6 回环、内网、链路本地、元数据、零地址等场景。
 *
 * @author OmniNest
 */
@DisplayName("SsrfSafeUrlValidator 安全验证测试")
class SsrfSafeUrlValidatorTest {
    private final SafeUrlValidator validator = new SsrfSafeUrlValidator();

    @Nested
    @DisplayName("IPv4 回环地址拦截")
    class LoopbackIpv4 {

        @ParameterizedTest
        @ValueSource(strings = {
                "http://127.0.0.1:8080/admin",
                "http://127.0.0.1/admin",
                "http://127.0.0.2/test",
                "http://127.255.255.255/test"
        })
        @DisplayName("拦截 127.0.0.0/8 段所有地址")
        void blocksLoopbackIpv4Range(String url) {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl(url))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("内网地址");
        }
    }

    @Nested
    @DisplayName("基准测试地址拦截")
    class BenchmarkAddresses {

        @ParameterizedTest
        @ValueSource(strings = {
                "http://198.18.0.1/audio",
                "http://198.19.255.254/audio"
        })
        @DisplayName("通用 SSRF 策略拦截 198.18.0.0/15 地址")
        void blocksBenchmarkIpv4Range(String url) {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl(url))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("内网地址");
        }
    }

    @Nested
    @DisplayName("IPv6 回环地址拦截")
    class LoopbackIpv6 {

        @Test
        @DisplayName("拦截 IPv6 回环地址 [::1]")
        void blocksIpv6Loopback() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://[::1]:8080/admin"))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("内网地址");
        }

        @Test
        @DisplayName("拦截 IPv6 回环地址 [0:0:0:0:0:0:0:1]")
        void blocksIpv6LoopbackFull() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://[0:0:0:0:0:0:0:1]/admin"))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("内网地址");
        }
    }

    @Nested
    @DisplayName("私有地址拦截")
    class PrivateAddresses {

        @ParameterizedTest
        @ValueSource(strings = {
                "http://10.0.0.1/admin",
                "http://10.255.255.255/admin",
                "http://10.10.10.10/test"
        })
        @DisplayName("拦截 10.0.0.0/8 段地址")
        void blocksPrivate10Range(String url) {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl(url))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("内网地址");
        }

        @ParameterizedTest
        @ValueSource(strings = {
                "http://172.16.0.1/admin",
                "http://172.31.255.255/admin",
                "http://172.20.0.1/test"
        })
        @DisplayName("拦截 172.16.0.0/12 段地址")
        void blocksPrivate172Range(String url) {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl(url))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("内网地址");
        }

        @ParameterizedTest
        @ValueSource(strings = {
                "http://192.168.1.1/admin",
                "http://192.168.0.1/admin",
                "http://192.168.255.255/test"
        })
        @DisplayName("拦截 192.168.0.0/16 段地址")
        void blocksPrivate192Range(String url) {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl(url))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("内网地址");
        }
    }

    @Nested
    @DisplayName("链路本地地址拦截")
    class LinkLocal {

        @ParameterizedTest
        @ValueSource(strings = {
                "http://169.254.169.254/metadata",
                "http://169.254.0.1/admin",
                "http://169.254.255.255/test"
        })
        @DisplayName("拦截 169.254.0.0/16 段地址（含云元数据）")
        void blocksLinkLocalIpv4(String url) {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl(url))
                    .isInstanceOf(BusinessException.class);
        }

        @Test
        @DisplayName("拦截 IPv6 链路本地地址 [fe80::1]")
        void blocksIpv6LinkLocal() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://[fe80::1]/admin"))
                    .isInstanceOf(BusinessException.class);
        }
    }

    @Nested
    @DisplayName("零地址拦截")
    class ZeroAddress {

        @Test
        @DisplayName("拦截 IPv4 零地址 0.0.0.0")
        void blocksIpv4Zero() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://0.0.0.0/admin"))
                    .isInstanceOf(BusinessException.class);
        }

        @Test
        @DisplayName("拦截 IPv4 非全零地址 0.x.x.x")
        void blocksIpv4ZeroPrefix() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://0.0.0.1/admin"))
                    .isInstanceOf(BusinessException.class);
        }
    }

    @Nested
    @DisplayName("云元数据服务拦截")
    class MetadataEndpoints {

        @Test
        @DisplayName("拦截 AWS/GCP 元数据地址 169.254.169.254")
        void blocksAwsMetadata() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://169.254.169.254/latest/meta-data/"))
                    .isInstanceOf(BusinessException.class);
        }

        @Test
        @DisplayName("拦截元数据主机名 metadata.google.internal")
        void blocksGoogleMetadataHostname() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://metadata.google.internal/computeMetadata/v1/"))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("内网地址");
        }

        @Test
        @DisplayName("拦截短主机名 metadata")
        void blocksShortMetadataHostname() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://metadata/latest/meta-data/"))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("内网地址");
        }
    }

    @Nested
    @DisplayName("本地主机名拦截")
    class LocalhostNames {

        @ParameterizedTest
        @ValueSource(strings = {
                "http://localhost/admin",
                "http://localhost:8080/admin",
                "http://LOCALHOST/admin"
        })
        @DisplayName("拦截 localhost 主机名")
        void blocksLocalhost(String url) {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl(url))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("内网地址");
        }

        @Test
        @DisplayName("拦截 *.localhost 子域")
        void blocksLocalhostSubdomain() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://app.localhost/admin"))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("内网地址");
        }
    }

    @Nested
    @DisplayName("IPv6 唯一本地地址拦截（ULA）")
    class UniqueLocalAddresses {

        @Test
        @DisplayName("拦截 fd00::/8 段地址")
        void blocksUlaAddress() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://[fd00::1]/admin"))
                    .isInstanceOf(BusinessException.class);
        }
    }

    @Nested
    @DisplayName("IPv6 embedded IPv4 blocking")
    class EmbeddedIpv4 {

        @ParameterizedTest
        @ValueSource(strings = {
                "http://[::ffff:127.0.0.1]/admin",
                "http://[::ffff:169.254.169.254]/metadata",
                "http://[::ffff:10.0.0.1]/admin",
                "http://[::ffff:192.168.1.1]/admin"
        })
        @DisplayName("block IPv4-mapped IPv6 loopback/metadata/private")
        void blocksIpv4Mapped(String url) {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl(url))
                    .isInstanceOf(BusinessException.class);
        }

        @Test
        @DisplayName("block NAT64 64:ff9b::/96 embedded private IPv4")
        void blocksNat64MappedPrivate() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://[64:ff9b::a00:1]/admin"))
                    .isInstanceOf(BusinessException.class);
        }

        @Test
        @DisplayName("block 6to4 2002::/16 embedded loopback IPv4")
        void blocks6to4MappedLoopback() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://[2002:7f00:1::]/admin"))
                    .isInstanceOf(BusinessException.class);
        }
    }

    @Nested
    @DisplayName("documentation and reserved IPv4 blocking")
    class DocumentationAndReserved {

        @ParameterizedTest
        @ValueSource(strings = {
                "http://192.0.0.1/test",
                "http://192.88.99.1/test",
                "http://198.51.100.1/test",
                "http://203.0.113.1/test"
        })
        @DisplayName("block TEST-NET and documentation ranges")
        void blocksDocumentationRanges(String url) {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl(url))
                    .isInstanceOf(BusinessException.class);
        }
    }

    @Nested
    @DisplayName("多播地址拦截")
    class Multicast {

        @Test
        @DisplayName("拦截 IPv4 多播地址")
        void blocksIpv4Multicast() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://224.0.0.1/admin"))
                    .isInstanceOf(BusinessException.class);
        }
    }

    @Nested
    @DisplayName("协议安全检查")
    class SchemeValidation {

        @ParameterizedTest
        @ValueSource(strings = {
                "ftp://example.com/file",
                "file:///etc/passwd",
                "gopher://example.com/",
                "jar:http://example.com!/evil"
        })
        @DisplayName("拦截非 HTTP/HTTPS 协议")
        void blocksNonHttpSchemes(String url) {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl(url))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("仅支持 HTTP 和 HTTPS");
        }

        @Test
        @DisplayName("拦截含用户信息的 URL")
        void blocksUserInfo() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http://user:pass@example.com/admin"))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("用户信息");
        }
    }

    @Nested
    @DisplayName("合法 URL 放行")
    class SafeUrls {

        @Test
        @DisplayName("公网域名应通过校验（固定 DNS stub）")
        void allowsPublicDomainWithStubbedDns() throws Exception {
            InetAddress publicAddress = InetAddress.getByName("8.8.8.8");
            SafeUrlValidator stubbed = new SsrfSafeUrlValidator(host -> new InetAddress[] {publicAddress});
            assertDoesNotThrow(() -> stubbed.requireSafeHttpUrl("https://files.example.com/file.zip"));
        }

        @Test
        @DisplayName("公网域名应通过校验（真实 DNS，可跳过）")
        void allowsPublicDomain() {
            /* 公网域名解析后得到非保留 IP，不应被拦截。
               DNS 解析依赖运行环境网络，使用 Assumptions 处理无网络场景；
               本机/代理环境可能把 example.com 解析到保留地址，同样跳过。 */
            Assumptions.assumeTrue(
                    resolvesToPublicAddress("example.com"),
                    "跳过：运行环境无法将 example.com 解析为公网地址");
            assertDoesNotThrow(() -> validator.requireSafeHttpUrl("https://example.com/file.zip"));
        }

        private boolean resolvesToPublicAddress(String host) {
            try {
                for (InetAddress address : InetAddress.getAllByName(host)) {
                    if (isBlockedLikeProduction(address)) {
                        return false;
                    }
                }
                return true;
            } catch (UnknownHostException exception) {
                return false;
            }
        }

        /** 与生产 isBlockedAddress 同口径：本机 DNS 可能把公网名解析到基准测试段。 */
        private boolean isBlockedLikeProduction(InetAddress address) {
            if (address.isAnyLocalAddress()
                    || address.isLoopbackAddress()
                    || address.isLinkLocalAddress()
                    || address.isSiteLocalAddress()
                    || address.isMulticastAddress()) {
                return true;
            }
            byte[] bytes = address.getAddress();
            if (bytes.length == 4) {
                int first = bytes[0] & 0xFF;
                int second = bytes[1] & 0xFF;
                return first == 0
                        || first == 10
                        || first == 127
                        || (first == 100 && second >= 64 && second <= 127)
                        || (first == 169 && second == 254)
                        || (first == 172 && second >= 16 && second <= 31)
                        || (first == 192 && second == 168)
                        || (first == 198 && (second == 18 || second == 19));
            }
            if (bytes.length == 16) {
                int first = bytes[0] & 0xFF;
                // 2001:2::/48 基准测试段；fc00::/7 唯一本地
                if (first == 0x20 && (bytes[1] & 0xFF) == 0x01 && (bytes[2] & 0xFF) == 0x00
                        && (bytes[3] & 0xFF) == 0x02) {
                    return true;
                }
                return (first & 0xFE) == 0xFC;
            }
            return false;
        }
    }

    @Nested
    @DisplayName("输入校验")
    class InputValidation {

        @Test
        @DisplayName("拒绝 null URL")
        void rejectsNull() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl(null))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("不能为空");
        }

        @Test
        @DisplayName("拒绝空字符串 URL")
        void rejectsBlank() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("   "))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("不能为空");
        }

        @Test
        @DisplayName("拒绝格式不正确的 URL")
        void rejectsMalformed() {
            /* 包含空格的 URL 会触发 URI.create 抛出 IllegalArgumentException */
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http:// example.com"))
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("格式不正确");
        }

        @Test
        @DisplayName("拒绝无主机名的 URL")
        void rejectsNoHost() {
            assertThatThrownBy(() -> validator.requireSafeHttpUrl("http:///path"))
                    .isInstanceOf(BusinessException.class);
        }
    }
}
