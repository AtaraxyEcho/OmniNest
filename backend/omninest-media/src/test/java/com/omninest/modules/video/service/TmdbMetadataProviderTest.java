package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.time.Duration;
import java.util.Arrays;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Test;

class TmdbMetadataProviderTest {

    private final MediaRuntimeConfigService configService = mock(MediaRuntimeConfigService.class);
    private final SafeUrlValidator safeUrlValidator = mock(SafeUrlValidator.class);
    private final TmdbMetadataProvider provider =
            new TmdbMetadataProvider(configService, safeUrlValidator);

    @Test
    void v3SearchUriUsesApiKeyWhenBothCredentialsConfigured() throws Exception {
        whenBaseUrl("https://api.themoviedb.org/3");
        when(configService.tmdbIncludeAdult()).thenReturn(false);

        URI uri = searchUri(new FileNameGuess("飞驰人生3", 2024, null, null), "test-key", "v4-token");

        assertThat(uri.toString()).startsWith("https://api.themoviedb.org/3/search/movie?");
        assertThat(uri.getRawQuery()).contains("query=%E9%A3%9E%E9%A9%B0%E4%BA%BA%E7%94%9F3");
        assertThat(uri.getRawQuery()).contains("api_key=test-key");
        assertThat(uri.getRawQuery()).contains("primary_release_year=2024");
        assertThat(uri.getRawQuery()).doesNotContain("&year=");
    }

    @Test
    void v4SearchUriUsesBearerCredentialWithoutApiKeyQuery() throws Exception {
        whenBaseUrl("https://api.themoviedb.org/4");
        when(configService.tmdbIncludeAdult()).thenReturn(true);

        URI uri = searchUri(new FileNameGuess("Some Show", 2020, 1, null), "test-key", "v4-token");

        assertThat(uri.toString()).startsWith("https://api.themoviedb.org/4/search/tv?");
        assertThat(uri.getRawQuery()).doesNotContain("api_key=");
        assertThat(uri.getRawQuery()).contains("include_adult=true");
        assertThat(uri.getRawQuery()).contains("first_air_date_year=2020");
    }

    @Test
    void searchQueriesUseConfiguredStrategy() throws Exception {
        when(configService.tmdbSearchQueriesStrategy()).thenReturn("NORMALIZED_ONLY");

        Method method = TmdbMetadataProvider.class.getDeclaredMethod("searchQueries", String.class);
        method.setAccessible(true);

        @SuppressWarnings("unchecked")
        Set<String> queries = (Set<String>) method.invoke(provider, "飞驰人生3");

        assertThat(queries).containsExactly("飞驰人生3");
    }

    @Test
    void requestsCarryConfiguredTimeoutAfterClientBecomesShared() throws Exception {
        whenBaseUrl("https://api.themoviedb.org/3");
        when(configService.tmdbTimeoutSeconds()).thenReturn(45);

        HttpRequest request = buildRequest();

        assertThat(request.timeout()).contains(Duration.ofSeconds(45));
    }

    @Test
    void requestTimeoutIsClampedToSupportedRange() throws Exception {
        whenBaseUrl("https://api.themoviedb.org/3");
        when(configService.tmdbTimeoutSeconds()).thenReturn(1);

        assertThat(buildRequest().timeout()).contains(Duration.ofSeconds(3));
    }

    /**
     * 每次请求新建 HttpClient 会留下选择器线程与连接池，客户端必须是唯一的 final 字段，
     * 且不得再有返回 HttpClient 的工厂方法。
     */
    @Test
    void httpClientIsASharedFinalFieldWithoutFactoryMethod() throws Exception {
        long clientFields = Arrays.stream(TmdbMetadataProvider.class.getDeclaredFields())
                .filter(field -> field.getType() == HttpClient.class)
                .count();
        assertThat(clientFields).isEqualTo(1L);

        Field clientField = TmdbMetadataProvider.class.getDeclaredField("httpClient");
        assertThat(Modifier.isFinal(clientField.getModifiers())).isTrue();
        assertThat(Arrays.stream(TmdbMetadataProvider.class.getDeclaredMethods())
                .filter(method -> method.getReturnType() == HttpClient.class))
                .isEmpty();
    }

    /**
     * 带着 API 凭据跟随跳转等于把凭据交给跳转目标，重定向策略必须是 NEVER。
     */
    @Test
    void sharedClientNeverFollowsRedirects() throws Exception {
        Field clientField = TmdbMetadataProvider.class.getDeclaredField("httpClient");
        clientField.setAccessible(true);
        HttpClient client = (HttpClient) clientField.get(provider);

        assertThat(client.followRedirects()).isEqualTo(HttpClient.Redirect.NEVER);
    }

    @Test
    void outboundUriRejectsUnsafeConfiguredBaseUrl() {
        List<String> rejected = List.of(
                "file:///etc/passwd",
                "http://169.254.169.254",
                "http://metadata.google.internal",
                "http://admin:pw@proxy.example/api"
        );

        for (String base : rejected) {
            whenBaseUrl(base);
            assertThatThrownBy(() -> apiUri("/search/movie", "query=a"))
                    .as(base)
                    .isInstanceOf(BusinessException.class);
        }
    }

    /**
     * 基址主机名正常但解析到受限地址段时，必须由校验器拦下。
     */
    @Test
    void outboundUriRejectsOriginResolvingToRestrictedSegment() {
        whenBaseUrl("https://tmdb-cache.example");
        doThrow(new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能指向本地或内网地址"))
                .when(safeUrlValidator)
                .requireSelfHostedSafeHost(any());

        assertThatThrownBy(() -> apiUri("/search/movie", "query=a"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    void outboundUriKeepsSelfHostedSidecarBaseUrlUsable() {
        whenBaseUrl("http://tmdb-proxy.lan:8080");

        assertThat(apiUri("/search/movie", "query=a").toString())
                .isEqualTo("http://tmdb-proxy.lan:8080/3/search/movie?query=a");
    }

    private URI apiUri(String path, String query) {
        try {
            Method method = TmdbMetadataProvider.class.getDeclaredMethod("apiUri", String.class, CharSequence.class);
            method.setAccessible(true);
            return (URI) method.invoke(provider, path, query);
        } catch (InvocationTargetException exception) {
            if (exception.getCause() instanceof RuntimeException runtimeException) {
                throw runtimeException;
            }
            throw new IllegalStateException(exception.getCause());
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException(exception);
        }
    }

    private HttpRequest buildRequest() throws Exception {
        Object credential = credential("test-key", null);
        Method method = TmdbMetadataProvider.class.getDeclaredMethod(
                "requestBuilder", URI.class, credential.getClass());
        method.setAccessible(true);
        HttpRequest.Builder builder = (HttpRequest.Builder) method.invoke(
                provider, URI.create("https://api.themoviedb.org/3/search/movie"), credential);
        return builder.GET().build();
    }

    private void whenBaseUrl(String baseUrl) {
        when(configService.tmdbBaseUrl()).thenReturn(baseUrl);
        when(configService.tmdbLanguage()).thenReturn("zh-CN");
    }

    private URI searchUri(FileNameGuess guess, String apiKey, String accessToken) throws Exception {
        Object credential = credential(apiKey, accessToken);
        boolean tv = guess.seasonNumber() != null;
        Method method = TmdbMetadataProvider.class.getDeclaredMethod(
                "searchUri",
                FileNameGuess.class,
                credential.getClass(),
                String.class,
                boolean.class,
                boolean.class
        );
        method.setAccessible(true);
        return (URI) method.invoke(provider, guess, credential, guess.title(), true, tv);
    }

    private Object credential(String apiKey, String accessToken) throws Exception {
        Class<?> type = Class.forName(TmdbMetadataProvider.class.getName() + "$TmdbCredential");
        Constructor<?> constructor = type.getDeclaredConstructor(String.class, String.class, int.class);
        constructor.setAccessible(true);
        return constructor.newInstance(apiKey, accessToken, apiVersion());
    }

    private int apiVersion() throws Exception {
        Method method = TmdbMetadataProvider.class.getDeclaredMethod("apiVersion");
        method.setAccessible(true);
        return (int) method.invoke(provider);
    }
}
