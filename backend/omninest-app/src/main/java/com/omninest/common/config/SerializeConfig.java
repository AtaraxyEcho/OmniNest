package com.omninest.common.config;

import com.fasterxml.jackson.annotation.JsonFormat;
import java.text.SimpleDateFormat;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import org.springframework.boot.jackson.autoconfigure.JsonMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import tools.jackson.databind.DeserializationFeature;

/**
 * 统一 JSON 序列化配置。
 *
 * <p>Web 边界由 Spring Boot 自动装配的 Jackson 3 转换器承担，这里仅保留与历史
 * 线格式一致的日期时间格式；null 字段维持输出（Jackson 默认行为，等价历史 WriteNulls）。
 *
 * <p>Jackson 3 把 {@code FAIL_ON_NULL_FOR_PRIMITIVES} 的默认值改成了开启，请求体里
 * record 的原始类型组件一旦缺席就整条绑定失败，客户端只能拿到「请求体格式不正确」。
 * 历史线格式（fastjson2 与 Jackson 2）都把缺席的布尔与数值按 {@code false}/{@code 0}
 * 处理，因此这里显式关回宽松：必填约束仍由 {@code @NotNull}、{@code @Min} 等校验给出
 * 明确错误，不再被解析层提前吞成格式错误。
 */
@Configuration
public class SerializeConfig {
    public static final String DATE_TIME_PATTERN = "yyyy-MM-dd HH:mm:ss";

    @Bean
    public JsonMapperBuilderCustomizer omniJsonFormatCustomizer() {
        return builder -> builder
                .disable(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)
                .defaultDateFormat(new SimpleDateFormat(DATE_TIME_PATTERN))
                .withConfigOverride(LocalDateTime.class,
                        override -> override.setFormat(JsonFormat.Value.forPattern(DATE_TIME_PATTERN)))
                .withConfigOverride(LocalDate.class,
                        override -> override.setFormat(JsonFormat.Value.forPattern("yyyy-MM-dd")))
                .withConfigOverride(LocalTime.class,
                        override -> override.setFormat(JsonFormat.Value.forPattern("HH:mm:ss")));
    }
}
