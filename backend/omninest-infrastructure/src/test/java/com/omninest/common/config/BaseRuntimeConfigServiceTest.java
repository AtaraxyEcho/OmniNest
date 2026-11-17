package com.omninest.common.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

class BaseRuntimeConfigServiceTest {

    private ConfigValueProvider stubProvider;
    private RuntimeConfigCache cacheService;
    private TestRuntimeConfigService service;

    @BeforeEach
    void setUp() {
        stubProvider = key -> Optional.empty();
        cacheService = mock(RuntimeConfigCache.class);
        when(cacheService.get(anyString())).thenReturn(Optional.empty());
        service = new TestRuntimeConfigService(stubProvider, cacheService);
    }

    /**
     * 测试用具体子类，暴露基类的 protected 方法。
     */
    private static class TestRuntimeConfigService extends BaseRuntimeConfigService {

        TestRuntimeConfigService(ConfigValueProvider configValueProvider, RuntimeConfigCache runtimeConfigCache) {
            super(configValueProvider, runtimeConfigCache);
        }

        boolean testBooleanConfig(String key, boolean defaultValue) {
            return booleanConfig(key, defaultValue);
        }

        String testStringConfig(String key, String defaultValue) {
            return stringConfig(key, defaultValue);
        }

        int testIntConfig(String key, int defaultValue) {
            return intConfig(key, defaultValue);
        }
    }

    @Nested
    @DisplayName("booleanConfig")
    class BooleanConfigTests {

        @Test
        @DisplayName("返回默认值当键不存在时")
        void returnsDefaultWhenKeyMissing() {
            assertThat(service.testBooleanConfig("missing.key", true)).isTrue();
            assertThat(service.testBooleanConfig("missing.key", false)).isFalse();
        }

        @Test
        @DisplayName("解析 true 值")
        void parsesTrueValues() {
            stubProvider = key -> Optional.of("true");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testBooleanConfig("key", false)).isTrue();

            stubProvider = key -> Optional.of("TRUE");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testBooleanConfig("key", false)).isTrue();

            stubProvider = key -> Optional.of("1");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testBooleanConfig("key", false)).isTrue();

            stubProvider = key -> Optional.of("yes");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testBooleanConfig("key", false)).isTrue();
        }

        @Test
        @DisplayName("解析 false 值")
        void parsesFalseValues() {
            stubProvider = key -> Optional.of("false");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testBooleanConfig("key", true)).isFalse();

            stubProvider = key -> Optional.of("FALSE");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testBooleanConfig("key", true)).isFalse();

            stubProvider = key -> Optional.of("0");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testBooleanConfig("key", true)).isFalse();

            stubProvider = key -> Optional.of("no");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testBooleanConfig("key", true)).isFalse();
        }

        @Test
        @DisplayName("无效布尔值返回默认值")
        void returnsDefaultForInvalidBoolean() {
            stubProvider = key -> Optional.of("invalid");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testBooleanConfig("key", true)).isTrue();
            assertThat(service.testBooleanConfig("key", false)).isFalse();
        }

        @Test
        @DisplayName("空字符串返回默认值")
        void returnsDefaultForBlankString() {
            stubProvider = key -> Optional.of("  ");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testBooleanConfig("key", true)).isTrue();
        }

        @Test
        @DisplayName("null 值返回默认值")
        void returnsDefaultForNullValue() {
            stubProvider = key -> Optional.empty();
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testBooleanConfig("key", false)).isFalse();
        }
    }

    @Nested
    @DisplayName("stringConfig")
    class StringConfigTests {

        @Test
        @DisplayName("返回默认值当键不存在时")
        void returnsDefaultWhenKeyMissing() {
            assertThat(service.testStringConfig("missing.key", "fallback")).isEqualTo("fallback");
        }

        @Test
        @DisplayName("返回并去除空白")
        void returnsTrimmedValue() {
            stubProvider = key -> Optional.of("  hello  ");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testStringConfig("key", "default")).isEqualTo("hello");
        }

        @Test
        @DisplayName("空白字符串返回默认值")
        void returnsDefaultForBlankString() {
            stubProvider = key -> Optional.of("   ");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testStringConfig("key", "default")).isEqualTo("default");
        }

        @Test
        @DisplayName("null 值返回默认值")
        void returnsDefaultForNullValue() {
            stubProvider = key -> Optional.empty();
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testStringConfig("key", "default")).isEqualTo("default");
        }

        @Test
        @DisplayName("返回正常字符串值")
        void returnsValidString() {
            stubProvider = key -> Optional.of("https://example.com");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testStringConfig("key", "default")).isEqualTo("https://example.com");
        }
    }

    @Nested
    @DisplayName("intConfig")
    class IntConfigTests {

        @Test
        @DisplayName("返回默认值当键不存在时")
        void returnsDefaultWhenKeyMissing() {
            assertThat(service.testIntConfig("missing.key", 42)).isEqualTo(42);
        }

        @Test
        @DisplayName("解析有效整数")
        void parsesValidInteger() {
            stubProvider = key -> Optional.of("8080");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testIntConfig("key", 0)).isEqualTo(8080);
        }

        @Test
        @DisplayName("解析带空白的整数")
        void parsesTrimmedInteger() {
            stubProvider = key -> Optional.of("  30  ");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testIntConfig("key", 0)).isEqualTo(30);
        }

        @Test
        @DisplayName("无效整数返回默认值")
        void returnsDefaultForInvalidInteger() {
            stubProvider = key -> Optional.of("not-a-number");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testIntConfig("key", 99)).isEqualTo(99);
        }

        @Test
        @DisplayName("空字符串返回默认值")
        void returnsDefaultForBlankString() {
            stubProvider = key -> Optional.of("  ");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testIntConfig("key", 7)).isEqualTo(7);
        }

        @Test
        @DisplayName("null 值返回默认值")
        void returnsDefaultForNullValue() {
            stubProvider = key -> Optional.empty();
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testIntConfig("key", 5)).isEqualTo(5);
        }

        @Test
        @DisplayName("负数整数正常解析")
        void parsesNegativeInteger() {
            stubProvider = key -> Optional.of("-1");
            service = new TestRuntimeConfigService(stubProvider, cacheService);
            assertThat(service.testIntConfig("key", 0)).isEqualTo(-1);
        }
    }
}
