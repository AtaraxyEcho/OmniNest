package com.omninest.modules.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.Ed25519Signer;
import com.nimbusds.jose.jwk.Curve;
import com.nimbusds.jose.jwk.OctetKeyPair;
import com.nimbusds.jose.util.Base64URL;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.modules.weather.dto.WeatherDto;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Base64;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestTemplate;
import tools.jackson.databind.JsonNode;

/**
 * 验证天气聚合、位置解析和 JWT 签名行为。
 *
 * @author OmniNest
 */
@ExtendWith(MockitoExtension.class)
class WeatherServiceTest {

    @Mock
    private ConfigValueProvider configValueProvider;
    @Mock
    private WeatherCacheStore weatherCacheStore;
    @Mock
    private RestTemplate restTemplate;
    @Mock
    private SafeUrlValidator safeUrlValidator;

    private WeatherService weatherService;

    @BeforeEach
    void setUp() {
        weatherService = new WeatherService(configValueProvider, weatherCacheStore, safeUrlValidator);
        ReflectionTestUtils.setField(weatherService, "restTemplate", restTemplate);
    }

    @Test
    @DisplayName("出站地址：元数据服务基址在请求前被拒绝")
    void apiUriRejectsMetadataBaseUrl() {
        assertThatThrownBy(() -> ReflectionTestUtils.invokeMethod(
                weatherService, "apiUri", "http://169.254.169.254", "/v7/weather/now"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("元数据服务");
    }

    @Test
    @DisplayName("出站地址：管理员配置的内网代理仍可请求")
    void apiUriKeepsConfiguredProxyOrigin() {
        URI uri = ReflectionTestUtils.invokeMethod(
                weatherService, "apiUri", "http://weather-proxy.lan:8080", "/v7/weather/now?location=1");

        assertThat(uri).isEqualTo(URI.create("http://weather-proxy.lan:8080/v7/weather/now?location=1"));
    }

    @Test
    @DisplayName("出站地址：基址解析到受限地址段时拒绝")
    void apiUriRejectsOriginResolvingToRestrictedSegment() {
        doThrow(new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能指向本地或内网地址"))
                .when(safeUrlValidator)
                .requireSelfHostedSafeHost(any(URI.class));

        assertThatThrownBy(() -> ReflectionTestUtils.invokeMethod(
                weatherService, "apiUri", "http://weather-cache.internal", "/v7/weather/now"))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("内网地址");
    }

    @Test
    @DisplayName("HTTP GET 不跟随跳转：Bearer JWT 不会随 3xx 送出")
    void httpGetDoesNotFollowRedirects() throws IOException {
        AtomicReference<String> leakedPath = new AtomicReference<>("");
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        int port = server.getAddress().getPort();
        server.createContext("/now", exchange -> {
            exchange.getResponseHeaders().set("Location", "http://127.0.0.1:" + port + "/leak");
            exchange.sendResponseHeaders(302, -1);
            exchange.close();
        });
        server.createContext("/leak", exchange -> {
            leakedPath.set(exchange.getRequestURI().getPath());
            byte[] body = "{\"code\":\"200\"}".getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, body.length);
            try (OutputStream responseBody = exchange.getResponseBody()) {
                responseBody.write(body);
            }
        });
        server.start();
        try {
            WeatherService localService = new WeatherService(configValueProvider, weatherCacheStore, safeUrlValidator);

            JsonNode result = ReflectionTestUtils.invokeMethod(
                    localService, "httpGet", URI.create("http://127.0.0.1:" + port + "/now"), "jwt");

            assertThat(result).isNull();
            assertThat(leakedPath.get()).isEmpty();
        } finally {
            server.stop(0);
        }
    }

    private Map<String, String> baseConfigs() {
        return Map.of(
            "weather.enabled", "true",
            "weather.qweather.base-url", "https://devapi.qweather.com",
            "weather.location", "116.41,39.92",
            "weather.qweather.project-id", "test-project",
            "weather.qweather.credential-id", "test-cred",
            "weather.qweather.private-key", generateTestEd25519Key()
        );
    }

    private void stubConfigs(Map<String, String> values) {
        when(configValueProvider.findByKey(anyString())).thenAnswer(invocation ->
            Optional.ofNullable(values.get(invocation.getArgument(0)))
        );
    }

    private void stubJwtCache() {
        when(weatherCacheStore.findJwt(anyString())).thenReturn(Optional.empty());
        when(weatherCacheStore.findWeather(anyString())).thenReturn(Optional.empty());
    }

    /**
     * 根据 URI 路径返回不同响应
     */
    @SuppressWarnings("unchecked")
    private void stubRestTemplateWithResponses(Map<String, String> pathToResponse) {
        when(restTemplate.exchange(
            any(URI.class),
            any(HttpMethod.class),
            any(),
            (Class<Object>) any()
        )).thenAnswer(invocation -> {
            URI uri = invocation.getArgument(0);
            String uriStr = uri.toString();
            for (var entry : pathToResponse.entrySet()) {
                if (uriStr.contains(entry.getKey())) {
                    return new ResponseEntity<>(
                        entry.getValue().getBytes(StandardCharsets.UTF_8),
                        HttpStatus.OK
                    );
                }
            }
            return new ResponseEntity<>("{}".getBytes(StandardCharsets.UTF_8), HttpStatus.OK);
        });
    }

    /** 空气质量 v1 响应（经纬度输入，直接调用 airquality） */
    private static final String AIR_QUALITY_V1_RESPONSE = """
        {
          "indexes":[
            {"code":"us-epa","name":"AQI (US)","aqi":46,"aqiDisplay":"46","level":"1","category":"Good"}
          ],
          "pollutants":[
            {"code":"pm2p5","name":"PM 2.5","concentration":{"value":11.0,"unit":"μg/m3"}}
          ]
        }
        """;

    /** GeoAPI 响应（LocationID 查询） */
    private static final String GEO_API_RESPONSE = """
        {
          "code":"200",
          "location":[
            {
              "id":"101260501",
              "name":"贵阳",
              "lat":"26.65",
              "lon":"106.71",
              "adm2":"贵阳",
              "adm1":"贵州",
              "country":"中国"
            }
          ]
        }
        """;

    @Nested
    @DisplayName("服务未启用时")
    class WhenDisabled {

        @Test
        @DisplayName("返回空天气数据")
        void returnsEmptyWeather() {
            stubConfigs(Map.of("weather.enabled", "false"));

            WeatherDto result = weatherService.getRealtimeWeather(null);

            assertThat(result.text()).isEqualTo("未知");
            assertThat(result.temp()).isZero();
        }

        @Test
        @DisplayName("配置读取中断时不缓存部分结果")
        void doesNotCachePartialConfiguration() {
            when(configValueProvider.findByKey(anyString())).thenAnswer(invocation -> {
                String key = invocation.getArgument(0);
                if ("weather.enabled".equals(key)) {
                    return Optional.of("true");
                }
                throw new IllegalStateException("config unavailable");
            });

            WeatherDto result = weatherService.getRealtimeWeather(null);

            assertThat(result.text()).isEqualTo("未知");
            assertThat(ReflectionTestUtils.getField(weatherService, "configCache"))
                    .isEqualTo(Map.of());
        }

        @Test
        @DisplayName("保留配置中心的 API 地址和默认位置")
        void keepsConfiguredEndpointAndLocation() {
            Map<String, String> configs = Map.of(
                    "weather.enabled", "false",
                    "weather.qweather.base-url", "https://weather.example/api",
                    "weather.location", "31.23,121.47"
            );
            stubConfigs(configs);

            weatherService.getRealtimeWeather(null);

            assertThat(ReflectionTestUtils.getField(weatherService, "configCache"))
                    .isEqualTo(Map.of(
                            "weather.enabled", "false",
                            "weather.qweather.url", "https://weather.example/api",
                            "weather.location", "31.23,121.47"
                    ));
        }
    }

    @Nested
    @DisplayName("聚合天气数据时（经纬度输入）")
    class AggregationWithLatLon {

        @Test
        @DisplayName("正确聚合实时天气 + 空气质量 + 预报")
        void aggregatesAllThreeApis() {
            stubConfigs(baseConfigs());
            stubJwtCache();

            Map<String, String> responses = new HashMap<>();
            responses.put("/v7/weather/now", """
                {
                  "code":"200",
                  "updateTime":"2025-06-01T12:00:00+08:00",
                  "now":{
                    "temp":"28","feelsLike":"30","text":"晴","icon":"100","humidity":"45",
                    "windSpeed":"12","windDir":"南风","pressure":"1013","vis":"25"
                  }
                }
                """);
            responses.put("/airquality/v1/current/", AIR_QUALITY_V1_RESPONSE);
            responses.put("/v7/weather/7d", """
                {
                  "code":"200",
                  "daily":[
                    {
                      "fxDate":"2025-06-01","sunrise":"04:50","sunset":"19:30","uvIndex":"7",
                      "tempMax":"30","tempMin":"22","iconDay":"100","textDay":"晴",
                      "iconNight":"150","textNight":"晴"
                    },
                    {
                      "fxDate":"2025-06-02","sunrise":"04:49","sunset":"19:31","uvIndex":"6",
                      "tempMax":"29","tempMin":"21","iconDay":"101","textDay":"多云",
                      "iconNight":"151","textNight":"多云"
                    }
                  ]
                }
                """);
            responses.put("/v7/weather/24h", """
                {
                  "code":"200",
                  "hourly":[
                    {"fxTime":"2025-06-01T13:00+08:00","temp":"28","icon":"100","text":"晴"},
                    {"fxTime":"2025-06-01T14:00+08:00","temp":"29","icon":"100","text":"晴"}
                  ]
                }
                """);
            stubRestTemplateWithResponses(responses);

            WeatherDto result = weatherService.getRealtimeWeather("116.41,39.92");

            assertThat(result.temp()).isEqualTo(28.0);
            assertThat(result.feelsLike()).isEqualTo(30.0);
            assertThat(result.text()).isEqualTo("晴");
            assertThat(result.humidity()).isEqualTo("45%");
            assertThat(result.aqi()).isEqualTo(46);
            assertThat(result.aqiCategory()).isEqualTo("Good");
            assertThat(result.hourly()).hasSize(2);
            assertThat(result.hourly().get(0).time()).isEqualTo("2025-06-01T13:00+08:00");
            assertThat(result.hourly().get(0).temp()).isEqualTo(28);
            assertThat(result.daily()).hasSize(2);
            assertThat(result.daily().get(0).date()).isEqualTo("2025-06-01");
            assertThat(result.daily().get(0).tempMax()).isEqualTo(30);
            assertThat(result.daily().get(0).textDay()).isEqualTo("晴");
            assertThat(result.pm2p5()).isEqualTo(11);
            assertThat(result.sunrise()).isEqualTo("04:50");
            assertThat(result.uvIndex()).isEqualTo(7);
        }

        @Test
        @DisplayName("空气质量请求失败时仍返回天气数据")
        void returnsWeatherWhenAirFails() {
            stubConfigs(baseConfigs());
            stubJwtCache();

            Map<String, String> responses = new HashMap<>();
            responses.put("/v7/weather/now", """
                {
                  "code":"200",
                  "updateTime":"2025-06-01T12:00:00+08:00",
                  "now":{
                    "temp":"25","feelsLike":"26","text":"多云","icon":"101","humidity":"60",
                    "windSpeed":"8","windDir":"东风","pressure":"1010","vis":"20"
                  }
                }
                """);
            responses.put("/v7/weather/7d", """
                {"code":"200","daily":[{"fxDate":"2025-06-01","sunrise":"04:50","sunset":"19:30","uvIndex":"5"}]}
                """);
            responses.put("/v7/weather/24h", """
                {"code":"200","hourly":[{"fxTime":"2025-06-01T13:00+08:00","temp":"25","icon":"101","text":"多云"}]}
                """);
            stubRestTemplateWithResponses(responses);

            WeatherDto result = weatherService.getRealtimeWeather("116.41,39.92");

            assertThat(result.temp()).isEqualTo(25.0);
            assertThat(result.aqi()).isZero();
            assertThat(result.aqiCategory()).isEqualTo("--");
        }

        @Test
        @DisplayName("实时天气请求失败时返回空数据")
        void returnsEmptyWhenWeatherNowFails() {
            stubConfigs(baseConfigs());
            stubJwtCache();

            Map<String, String> responses = new HashMap<>();
            responses.put("/v7/weather/now", "{\"code\":\"500\"}");
            stubRestTemplateWithResponses(responses);

            WeatherDto result = weatherService.getRealtimeWeather("116.41,39.92");

            assertThat(result.text()).isEqualTo("未知");
        }
    }

    @Nested
    @DisplayName("LocationID 输入（需要 GeoAPI 转换）")
    class LocationIdInput {

        @Test
        @DisplayName("LocationID 通过 GeoAPI 转换为经纬度后调用空气质量 API")
        void locationIdConvertedViaGeoApi() {
            Map<String, String> configs = new HashMap<>(baseConfigs());
            configs.put("weather.location", "贵阳");
            stubConfigs(configs);
            stubJwtCache();

            Map<String, String> responses = new HashMap<>();
            // GeoAPI 响应
            responses.put("/geo/v2/city/lookup", GEO_API_RESPONSE);
            // 天气 API 响应（使用 LocationID）
            responses.put("/v7/weather/now", """
                {
                  "code":"200",
                  "updateTime":"2025-06-01T12:00:00",
                  "now":{
                    "temp":"22","feelsLike":"22","text":"多云","icon":"101","humidity":"65",
                    "windSpeed":"6","windDir":"东风","pressure":"1012","vis":"15"
                  }
                }
                """);
            responses.put("/v7/weather/7d", """
                {"code":"200","daily":[{"fxDate":"2025-06-01","sunrise":"06:00","sunset":"19:30","uvIndex":"5"}]}
                """);
            // 空气质量 API 响应（经纬度路径参数）
            responses.put("/airquality/v1/current/", AIR_QUALITY_V1_RESPONSE);
            stubRestTemplateWithResponses(responses);

            WeatherDto result = weatherService.getRealtimeWeather("101260501");

            assertThat(result.temp()).isEqualTo(22.0);
            assertThat(result.aqi()).isEqualTo(46);
            assertThat(result.pm2p5()).isEqualTo(11);
        }
    }

    @Nested
    @DisplayName("WeatherDto.empty()")
    class EmptyDto {

        @Test
        @DisplayName("返回安全的默认值")
        void returnsSafeDefaults() {
            WeatherDto empty = WeatherDto.empty();

            assertThat(empty.temp()).isZero();
            assertThat(empty.text()).isEqualTo("未知");
            assertThat(empty.icon()).isEqualTo("999");
            assertThat(empty.humidity()).isEqualTo("--");
            assertThat(empty.sunrise()).isEqualTo("--");
            assertThat(empty.aqiCategory()).isEqualTo("--");
        }
    }

    @Nested
    @DisplayName("JWT 生成")
    class JwtGeneration {

        @Test
        @DisplayName("Ed25519 测试密钥可正常解析和签名")
        void testKeyCanBeUsedForSigning() throws Exception {
            String pem = generateTestEd25519Key();
            String base64 = pem
                    .replace("-----BEGIN PRIVATE KEY-----", "")
                    .replace("-----END PRIVATE KEY-----", "")
                    .replaceAll("\\s", "");
            byte[] pkcs8Bytes = Base64.getDecoder().decode(base64);

            PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(pkcs8Bytes);
            KeyFactory kf = KeyFactory.getInstance("Ed25519");
            PrivateKey privateKey = kf.generatePrivate(keySpec);

            assertThat(privateKey).isNotNull();
            assertThat(privateKey.getEncoded()).isNotNull();

            byte[] rawKey = new byte[32];
            byte[] encoded = privateKey.getEncoded();
            System.arraycopy(encoded, encoded.length - 32, rawKey, 0, 32);
            Base64URL d = Base64URL.encode(rawKey);
            Base64URL x = Base64URL.encode(new byte[32]);
            OctetKeyPair okp = new OctetKeyPair.Builder(
                    Curve.Ed25519, x).d(d).build();

            JWSHeader header = new JWSHeader.Builder(
                    JWSAlgorithm.EdDSA).keyID("test-cred").build();
            JWTClaimsSet claims = new JWTClaimsSet.Builder()
                    .subject("test-project")
                    .issueTime(new Date())
                    .expirationTime(new Date(System.currentTimeMillis() + 3600000))
                    .build();
            SignedJWT jwt = new SignedJWT(header, claims);
            jwt.sign(new Ed25519Signer(okp));

            String token = jwt.serialize();
            assertThat(token).isNotEmpty();
            assertThat(token.split("\\.")).hasSize(3);
        }

        @Test
        @DisplayName("端到端：配置加载 + JWT 生成 + API 调用")
        void endToEndWeatherFetch() {
            stubConfigs(baseConfigs());
            stubJwtCache();

            Map<String, String> responses = new HashMap<>();
            responses.put("/v7/weather/now", """
                    {
                      "code":"200",
                      "updateTime":"2025-06-01T12:00:00",
                      "now":{
                        "temp":"10","feelsLike":"10","text":"晴","icon":"100","humidity":"50",
                        "windSpeed":"5","windDir":"北风","pressure":"1013","vis":"10"
                      }
                    }
                    """);
            responses.put("/airquality/v1/current/", AIR_QUALITY_V1_RESPONSE);
            responses.put("/v7/weather/7d", "{\"code\":\"200\",\"daily\":[]}");
            stubRestTemplateWithResponses(responses);

            WeatherDto result = weatherService.getRealtimeWeather("116.41,39.92");

            assertThat(result.temp()).isEqualTo(10.0);
            assertThat(result.aqi()).isEqualTo(46);
        }
    }

    @Nested
    @DisplayName("按界面语言请求与缓存")
    class LanguageAndCacheKey {

        private static final String NOW_RESPONSE = """
            {
              "code":"200",
              "updateTime":"2025-06-01T12:00:00+08:00",
              "now":{
                "temp":"28","feelsLike":"30","text":"晴","icon":"100","humidity":"45",
                "windSpeed":"12","windDir":"南风","pressure":"1013","vis":"25"
              }
            }
            """;

        /** 以指定语言发起一次聚合查询，返回全部出站 URI。 */
        @SuppressWarnings("unchecked")
        private List<String> requestedUris(String lang) {
            stubConfigs(baseConfigs());
            stubJwtCache();
            Map<String, String> responses = new HashMap<>();
            responses.put("/v7/weather/now", NOW_RESPONSE);
            stubRestTemplateWithResponses(responses);

            weatherService.getRealtimeWeather("116.41,39.92", null, lang);

            ArgumentCaptor<URI> captor = ArgumentCaptor.forClass(URI.class);
            verify(restTemplate, times(4))
                    .exchange(captor.capture(), any(HttpMethod.class), any(), (Class<Object>) any());
            return captor.getAllValues().stream().map(URI::toString).toList();
        }

        @Test
        @DisplayName("带文案的四个调用都带上请求语言")
        void passesLangOnEveryTextBearingCall() {
            List<String> uris = requestedUris("en");

            assertThat(uris).hasSize(4);
            assertThat(uris).allSatisfy(uri -> assertThat(uri).endsWith("lang=en"));
            assertThat(uris).anyMatch(uri -> uri.contains("/v7/weather/now"));
            assertThat(uris).anyMatch(uri -> uri.contains("/v7/weather/7d"));
            assertThat(uris).anyMatch(uri -> uri.contains("/v7/weather/24h"));
            assertThat(uris).anyMatch(uri -> uri.contains("/airquality/v1/current/"));
        }

        @Test
        @DisplayName("缓存键带语言，避免中文文案被英文用户复用")
        void keysWeatherCacheByLanguage() {
            requestedUris("en");

            verify(weatherCacheStore).findWeather("116.41,39.92:en");
            verify(weatherCacheStore).saveWeather(eq("116.41,39.92:en"), any(WeatherDto.class));
        }

        @Test
        @DisplayName("白名单外的语言码回落到中文，不原样拼进入站 URL")
        void fallsBackOutsideWhitelist() {
            assertThat(WeatherService.normalizeLang(null)).isEqualTo("zh");
            assertThat(WeatherService.normalizeLang("zh-Hans")).isEqualTo("zh");
            assertThat(WeatherService.normalizeLang("EN-us")).isEqualTo("en");
            assertThat(WeatherService.normalizeLang("ru")).isEqualTo("zh");
            assertThat(WeatherService.normalizeLang("en&lang=zh")).isEqualTo("zh");

            assertThat(requestedUris("en&lang=zh"))
                    .allSatisfy(uri -> assertThat(uri).endsWith("lang=zh"));
        }
    }

    private String generateTestEd25519Key() {
        byte[] pkcs8 = new byte[48];
        pkcs8[0] = 0x30; pkcs8[1] = 0x2e;
        pkcs8[2] = 0x02; pkcs8[3] = 0x01; pkcs8[4] = 0x00;
        pkcs8[5] = 0x30; pkcs8[6] = 0x05;
        pkcs8[7] = 0x06; pkcs8[8] = 0x03; pkcs8[9] = 0x2b; pkcs8[10] = 0x65; pkcs8[11] = 0x70;
        pkcs8[12] = 0x04; pkcs8[13] = 0x22;
        pkcs8[14] = 0x04; pkcs8[15] = 0x20;
        for (int i = 16; i < 48; i++) {
            pkcs8[i] = (byte) (i - 15);
        }
        Base64.Encoder encoder = Base64.getEncoder();
        String base64 = encoder.encodeToString(pkcs8);
        return "-----BEGIN PRIVATE KEY-----\n" + base64 + "\n-----END PRIVATE KEY-----";
    }
}
