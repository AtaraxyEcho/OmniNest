package com.omninest.common.config;

import com.fasterxml.jackson.annotation.JsonFormat;
import java.text.SimpleDateFormat;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import org.springframework.boot.jackson.autoconfigure.JsonMapperBuilderCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 统一 JSON 序列化配置。
 *
 * <p>Web 边界由 Spring Boot 自动装配的 Jackson 3 转换器承担，这里仅保留与历史
 * 线格式一致的日期时间格式；null 字段维持输出（Jackson 默认行为，等价历史 WriteNulls）。
 */
@Configuration
public class SerializeConfig {
    public static final String DATE_TIME_PATTERN = "yyyy-MM-dd HH:mm:ss";

    @Bean
    public JsonMapperBuilderCustomizer omniJsonFormatCustomizer() {
        return builder -> builder
                .defaultDateFormat(new SimpleDateFormat(DATE_TIME_PATTERN))
                .withConfigOverride(LocalDateTime.class,
                        override -> override.setFormat(JsonFormat.Value.forPattern(DATE_TIME_PATTERN)))
                .withConfigOverride(LocalDate.class,
                        override -> override.setFormat(JsonFormat.Value.forPattern("yyyy-MM-dd")))
                .withConfigOverride(LocalTime.class,
                        override -> override.setFormat(JsonFormat.Value.forPattern("HH:mm:ss")));
    }
}
