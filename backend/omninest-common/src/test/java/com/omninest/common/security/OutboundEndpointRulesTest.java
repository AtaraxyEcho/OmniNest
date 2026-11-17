package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 出站接口地址规则测试。
 *
 * @author OmniNest
 */
class OutboundEndpointRulesTest {

    private final RecordingSafeUrlValidator validator = new RecordingSafeUrlValidator();

    @Test
    @DisplayName("配置基址只接受 HTTP 与 HTTPS")
    void rejectsNonHttpSchemes() {
        List<String> rejected = List.of(
                "file:///etc/passwd",
                "gopher://127.0.0.1:11211/x",
                "ftp://internal.example/api"
        );

        for (String value : rejected) {
            assertThatThrownBy(() -> OutboundEndpointRules.parseConfiguredBaseUrl(value))
                    .as(value)
                    .isInstanceOfSatisfying(BusinessException.class, exception ->
                            assertThat(exception.errorCode()).isEqualTo(ErrorCode.BAD_REQUEST));
        }
    }

    @Test
    @DisplayName("配置基址拒绝用户信息段与缺失主机")
    void rejectsUserInfoAndMissingHost() {
        assertThatThrownBy(() -> OutboundEndpointRules.parseConfiguredBaseUrl("http://admin:pw@proxy.example/api"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("不允许携带用户信息");
        assertThatThrownBy(() -> OutboundEndpointRules.parseConfiguredBaseUrl("http:///api"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("缺少主机名");
        assertThatThrownBy(() -> OutboundEndpointRules.parseConfiguredBaseUrl(" "))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("未配置");
    }

    @Test
    @DisplayName("元数据服务地址在任何配置下都被拒绝")
    void rejectsMetadataHosts() {
        List<String> blocked = List.of(
                "http://169.254.169.254/latest/meta-data",
                "http://metadata.google.internal/computeMetadata/v1",
                "http://metadata/"
        );

        for (String value : blocked) {
            assertThatThrownBy(() -> OutboundEndpointRules.parseConfiguredBaseUrl(value))
                    .as(value)
                    .isInstanceOf(BusinessException.class)
                    .hasMessageContaining("元数据服务");
        }
    }

    @Test
    @DisplayName("本机与内网 sidecar 按超级管理员的配置放行，但基址仍要过自建端点档位")
    void allowsSelfHostedSidecarOrigins() {
        assertThatCode(() -> OutboundEndpointRules.requireConfiguredEndpoint(
                "http://localhost:3001",
                URI.create("http://localhost:3001/cloudsearch?keywords=a"),
                validator)).doesNotThrowAnyException();
        assertThatCode(() -> OutboundEndpointRules.requireConfiguredEndpoint(
                "http://192.168.1.20:8080/tmdb",
                URI.create("http://192.168.1.20:8080/tmdb/3/search/movie"),
                validator)).doesNotThrowAnyException();
        assertThat(validator.selfHostChecked)
                .containsExactly(
                        URI.create("http://localhost:3001"),
                        URI.create("http://192.168.1.20:8080/tmdb"));
    }

    @Test
    @DisplayName("基址解析落到受限地址段时拒绝，即使主机名看起来正常")
    void rejectsOriginResolvingToRestrictedSegment() {
        URI origin = URI.create("http://internal-proxy.example");
        validator.rejectSelfHosted(origin);

        assertThatThrownBy(() -> OutboundEndpointRules.requireConfiguredEndpoint(
                "http://internal-proxy.example",
                URI.create("http://internal-proxy.example/latest/meta-data"),
                validator))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    @DisplayName("请求地址必须停留在基址同源，端口或协议不同也算逃逸")
    void rejectsRequestOutsideConfiguredOrigin() {
        assertThatThrownBy(() -> OutboundEndpointRules.requireConfiguredEndpoint(
                "https://api.themoviedb.org/3",
                URI.create("https://attacker.example/3/search/movie"),
                validator))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("偏离配置的基址");
        assertThatThrownBy(() -> OutboundEndpointRules.requireConfiguredEndpoint(
                "https://api.themoviedb.org/3",
                URI.create("http://api.themoviedb.org/3/search/movie"),
                validator))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("偏离配置的基址");
        assertThatThrownBy(() -> OutboundEndpointRules.requireConfiguredEndpoint(
                "http://localhost:3001",
                URI.create("http://localhost:5432/query"),
                validator))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("偏离配置的基址");
    }

    @Test
    @DisplayName("请求地址侧的元数据主机检查独立于同源检查")
    void rejectsMetadataHostOnRequestAddress() {
        assertThatThrownBy(() -> OutboundEndpointRules.requireConfiguredEndpoint(
                "http://localhost:3001",
                URI.create("http://169.254.169.254/latest/meta-data"),
                validator))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("元数据服务");
        assertThatCode(() -> OutboundEndpointRules.requireConfiguredEndpoint(
                "https://api.themoviedb.org/3",
                URI.create("https://api.themoviedb.org/3/search/movie?query=a"),
                validator))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("内置公网服务地址交由校验器按解析结果判定")
    void publicEndpointDelegatesResolutionCheck() {
        URI target = URI.create("https://lrclib.net/api/get?track_name=a");

        assertThat(OutboundEndpointRules.requirePublicEndpoint(target, validator)).isEqualTo(target);
        assertThat(validator.checked).containsExactly(target);

        URI blocked = URI.create("https://lrclib.net/private");
        validator.reject(blocked);
        assertThatThrownBy(() -> OutboundEndpointRules.requirePublicEndpoint(blocked, validator))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网");
    }

    @Test
    @DisplayName("内置公网服务地址先校验协议再查解析结果")
    void publicEndpointRejectsNonHttpBeforeResolving() {
        assertThatThrownBy(() -> OutboundEndpointRules.requirePublicEndpoint(
                URI.create("file:///etc/passwd"), validator))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("仅支持 HTTP 和 HTTPS");
        assertThat(validator.checked).isEmpty();
    }

    /**
     * 记录被校验地址的测试替身，可按地址预设拒绝结果。
     */
    private static final class RecordingSafeUrlValidator implements SafeUrlValidator {
        private final List<URI> checked = new ArrayList<>();
        private final List<URI> selfHostChecked = new ArrayList<>();
        private URI rejectedUri;
        private URI rejectedSelfHostedUri;

        void reject(URI uri) {
            rejectedUri = uri;
        }

        void rejectSelfHosted(URI uri) {
            rejectedSelfHostedUri = uri;
        }

        @Override
        public void requireSafeHost(URI uri) {
            requireSafeHost(uri, false);
        }

        @Override
        public void requireSafeHost(URI uri, boolean allowSiteLocal) {
            checked.add(uri);
            if (uri.equals(rejectedUri)) {
                throw new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能指向本地或内网地址");
            }
        }

        @Override
        public void requireSelfHostedSafeHost(URI uri) {
            selfHostChecked.add(uri);
            if (uri.equals(rejectedSelfHostedUri)) {
                throw new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能指向本地或内网地址");
            }
        }

        @Override
        public void requireSafeHttpUrl(String url) {
            requireSafeHost(URI.create(url));
        }
    }
}
