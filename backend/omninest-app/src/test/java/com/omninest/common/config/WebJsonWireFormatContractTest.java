package com.omninest.common.config;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.file.dto.CreateShareLinkRequest;
import java.time.LocalDateTime;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.json.JsonTest;
import org.springframework.context.annotation.Import;
import tools.jackson.databind.ObjectMapper;

/**
 * Web 层 JSON 线格式契约：钉死 Jackson 3 迁移后与历史 fastjson2 线格式的等价行为，
 * 防止依赖升级或配置改动在无感知的情况下改变 API 出入参形状。
 *
 * @author OmniNest
 */
@JsonTest
@Import(SerializeConfig.class)
class WebJsonWireFormatContractTest {

    @Autowired
    private ObjectMapper objectMapper;

    record SamplePayload(String name, Integer count, LocalDateTime seenAt, Weather condition) {
    }

    enum Weather {
        SUNNY,
        RAIN_Y
    }

    @Test
    void writesNullFieldsEnumNamesAndLegacyDateTimePattern() {
        String json = objectMapper.writeValueAsString(new SamplePayload(
                "alpha", null, LocalDateTime.of(2026, 10, 2, 11, 30, 0), Weather.SUNNY));

        // null 字段必须上桥（等价历史 WriteNulls）
        assertThat(json).contains("\"count\":null");
        // 枚举按名称输出（等价历史 WriteEnumsUsingName）
        assertThat(json).contains("\"condition\":\"SUNNY\"");
        // 时间线格式保持 yyyy-MM-dd HH:mm:ss
        assertThat(json).contains("\"seenAt\":\"2026-10-02 11:30:00\"");
    }

    @Test
    void deserializesLenientlyLikeLegacyWireFormat() {
        // 未知字段忽略，且字符串数字可绑定到数值字段（等价历史 SupportSmartMatch 的宽松面）
        SamplePayload parsed = objectMapper.readValue("""
                {"name":"alpha","count":"7","seenAt":"2026-10-02 11:30:00",
                 "condition":"SUNNY","extraUnknownField":true}
                """, SamplePayload.class);
        assertThat(parsed.count()).isEqualTo(7);

        // 数字可绑定到字符串字段
        SamplePayload coerced = objectMapper.readValue(
                "{\"name\":123,\"count\":1,\"seenAt\":\"2026-10-02 11:30:00\",\"condition\":\"SUNNY\"}",
                SamplePayload.class);
        assertThat(coerced.name()).isEqualTo("123");
    }

    @Test
    void optionalFlagMayBeOmittedFromShareRequest() {
        // 文档标称选填的开关必须能整体缺席；此前它是原始类型组件，
        // 缺席即绑定失败，客户端只拿到「请求体格式不正确或枚举值不受支持」。
        CreateShareLinkRequest omitted = objectMapper.readValue("""
                {"resourceId":"550e8400-e29b-41d4-a716-446655440000","resourceType":"FOLDER"}
                """, CreateShareLinkRequest.class);
        assertThat(omitted.generatePassword()).isFalse();
        assertThat(omitted.parsedExpiresAt()).isNull();

        CreateShareLinkRequest explicit = objectMapper.readValue("""
                {"resourceId":"550e8400-e29b-41d4-a716-446655440000","resourceType":"FOLDER",
                 "generatePassword":true}
                """, CreateShareLinkRequest.class);
        assertThat(explicit.generatePassword()).isTrue();
    }

    @Test
    void apiResponseKeepsNullDetailsOnWire() {
        String json = objectMapper.writeValueAsString(ApiResponse.error(ErrorCode.PARAM_ERROR, "参数错误"));

        assertThat(json).contains("\"details\":null");
        assertThat(json).contains("\"errorName\":\"PARAM_ERROR\"");
    }
}
