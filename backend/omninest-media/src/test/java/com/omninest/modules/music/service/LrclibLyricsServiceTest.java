package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.net.URI;
import java.net.http.HttpClient;
import org.junit.jupiter.api.Test;

/**
 * LRCLIB 出站地址校验测试：基址是代码内置常量，仍要按公网地址逐次复核。
 *
 * @author OmniNest
 */
class LrclibLyricsServiceTest {

    private final SafeUrlValidator safeUrlValidator = mock(SafeUrlValidator.class);
    private final LrclibLyricsService service = new LrclibLyricsService(safeUrlValidator);

    @Test
    void requestAddressIsCheckedAsPublicEndpoint() throws Exception {
        URI uri = safeUri("/get?track_name=a");

        assertThat(uri.toString()).isEqualTo("https://lrclib.net/api/get?track_name=a");
        verify(safeUrlValidator).requireSafeHost(uri);
    }

    @Test
    void blockedResolutionIsRejectedBeforeRequest() {
        doThrow(new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能指向本地或内网地址"))
                .when(safeUrlValidator)
                .requireSafeHost(any(URI.class));

        assertThatThrownBy(() -> safeUri("/get?track_name=a"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    void sharedClientNeverFollowsRedirects() throws Exception {
        Field field = LrclibLyricsService.class.getDeclaredField("httpClient");
        field.setAccessible(true);
        HttpClient client = (HttpClient) field.get(service);

        assertThat(client.followRedirects()).isEqualTo(HttpClient.Redirect.NEVER);
    }

    private URI safeUri(String path) {
        try {
            Method method = LrclibLyricsService.class.getDeclaredMethod("safeUri", String.class);
            method.setAccessible(true);
            return (URI) method.invoke(service, path);
        } catch (InvocationTargetException exception) {
            if (exception.getCause() instanceof RuntimeException runtimeException) {
                throw runtimeException;
            }
            throw new IllegalStateException(exception.getCause());
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException(exception);
        }
    }
}
