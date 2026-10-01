package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.alibaba.fastjson2.JSON;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.modules.file.config.ExternalStorageEndpointPolicyProperties;
import java.net.URI;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 外部存储端点出网安全守卫测试。
 * 覆盖协议白名单、用户信息、端口白名单与内网地址策略开关。
 *
 * @author OmniNest
 */
@DisplayName("ExternalStorageEndpointGuard 端点安全测试")
class ExternalStorageEndpointGuardTest {

    private final SafeUrlValidator safeUrlValidator = mock(SafeUrlValidator.class);
    private final ExternalStorageEndpointPolicyProperties properties =
            new ExternalStorageEndpointPolicyProperties();

    private ExternalStorageEndpointGuard guard() {
        return new ExternalStorageEndpointGuard(safeUrlValidator, properties);
    }

    @Test
    @DisplayName("WEBDAV 公网地址按开关状态校验主机")
    void validatesWebdavUrlThroughHostValidator() {
        properties.setAllowPrivateNetwork(false);
        guard().validate("WEBDAV", JSON.parseObject("{\"url\":\"https://dav.example.com/dav\"}"));

        verify(safeUrlValidator).requireSafeHost(any(URI.class), anyBoolean());
    }

    @Test
    @DisplayName("WEBDAV 内网地址默认被拒并给出开关指引")
    void rejectsPrivateWebdavUrlByDefaultWithHint() {
        doThrow(new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能指向本地或内网地址"))
                .when(safeUrlValidator).requireSafeHost(any(URI.class), anyBoolean());

        assertThatThrownBy(() -> guard().validate("WEBDAV",
                        JSON.parseObject("{\"url\":\"http://192.168.1.10/dav\"}")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("allow-private-network");
    }

    @Test
    @DisplayName("非 HTTP(S) 协议与携带用户信息的地址被拒")
    void rejectsNonHttpSchemeAndUserInfo() {
        assertThatThrownBy(() -> guard().validate("WEBDAV", JSON.parseObject("{\"url\":\"ftp://dav.example.com\"}")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("HTTP/HTTPS");
        assertThatThrownBy(() -> guard().validate("S3",
                        JSON.parseObject("{\"endpoint\":\"https://user:pass@s3.example.com\"}")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("用户信息");
    }

    @Test
    @DisplayName("端口不在白名单时被拒，白名单可扩展")
    void rejectsPortsOutsideWhitelist() {
        assertThatThrownBy(() -> guard().validate("WEBDAV",
                        JSON.parseObject("{\"url\":\"https://dav.example.com:6379\"}")))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("端口不在允许清单");

        properties.setAllowedPorts(new java.util.ArrayList<>(java.util.List.of(80, 443, 6379)));
        assertThatCode(() -> guard().validate("WEBDAV",
                        JSON.parseObject("{\"url\":\"https://dav.example.com:6379\"}")))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("OAuth 连接器与未填写端点的凭据直接放行")
    void skipsOAuthAndMissingEndpoint() {
        assertThatCode(() -> guard().validate("GDRIVE",
                        JSON.parseObject("{\"access_token\":\"token\"}")))
                .doesNotThrowAnyException();
        assertThatCode(() -> guard().validate("WEBDAV", Map.of()))
                .doesNotThrowAnyException();
    }
}
