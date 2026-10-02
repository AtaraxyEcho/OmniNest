package com.omninest.common.json;

import com.fasterxml.jackson.annotation.JsonInclude;
import java.lang.reflect.Type;
import java.util.List;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * 进程内共享的 Jackson 3 JSON 访问入口。
 *
 * <p>面向任务载荷、消息体、Redis 缓存与外部服务报文等非 Web 边界场景；Web 层
 * 的请求与响应序列化由 Spring Boot 自动装配的 JsonMapper 负责，配置见 SerializeConfig。
 * 序列化忽略 null 字段，与历史 fastjson2 默认线格式保持一致。
 *
 * @author OmniNest
 */
public final class JsonSupport {

    private static final JsonMapper MAPPER = JsonMapper.builder()
            .changeDefaultPropertyInclusion(value -> value
                    .withValueInclusion(JsonInclude.Include.NON_NULL))
            .build();

    private JsonSupport() {
    }

    /**
     * 返回共享 JsonMapper，仅供需要树转换等高级能力的调用方使用。
     *
     * @return 只读共享映射器实例
     */
    public static JsonMapper mapper() {
        return MAPPER;
    }

    /**
     * 序列化为 JSON 字符串。
     *
     * @param value 待序列化对象
     * @return JSON 字符串
     */
    public static String toJson(Object value) {
        return MAPPER.writeValueAsString(value);
    }

    /**
     * 序列化为 UTF-8 JSON 字节。
     *
     * @param value 待序列化对象
     * @return JSON 字节数组
     */
    public static byte[] toBytes(Object value) {
        return MAPPER.writeValueAsBytes(value);
    }

    /**
     * 反序列化为指定类型。
     *
     * @param json JSON 字符串
     * @param type 目标类型
     * @param <T> 目标类型参数
     * @return 反序列化结果
     */
    public static <T> T fromJson(String json, Class<T> type) {
        return MAPPER.readValue(json, type);
    }

    /**
     * 反序列化 UTF-8 JSON 字节为指定类型。
     *
     * @param json JSON 字节
     * @param type 目标类型
     * @param <T> 目标类型参数
     * @return 反序列化结果
     */
    public static <T> T fromJson(byte[] json, Class<T> type) {
        return MAPPER.readValue(json, type);
    }

    /**
     * 反序列化为泛型类型。
     *
     * @param json JSON 字符串
     * @param type 泛型目标类型
     * @param <T> 目标类型参数
     * @return 反序列化结果
     */
    public static <T> T fromJson(String json, TypeReference<T> type) {
        return MAPPER.readValue(json, type);
    }

    /**
     * 反序列化为反射类型，供消息监听等运行期才能确定目标类型的场景使用。
     *
     * @param json UTF-8 JSON 字节
     * @param type 反射目标类型
     * @param <T> 目标类型参数
     * @return 反序列化结果
     */
    public static <T> T fromJson(byte[] json, Type type) {
        return MAPPER.readValue(json, MAPPER.constructType(type));
    }

    /**
     * 反序列化 JSON 数组为元素类型列表。
     *
     * @param json JSON 字符串
     * @param elementType 列表元素类型
     * @param <T> 元素类型参数
     * @return 元素列表
     */
    public static <T> List<T> listFrom(String json, Class<T> elementType) {
        return MAPPER.readValue(json,
                MAPPER.getTypeFactory().constructCollectionType(List.class, elementType));
    }

    /**
     * 解析为 JsonNode 树，用于结构不确定或需要逐字段导航的报文。
     *
     * @param json JSON 字符串
     * @return JSON 树
     */
    public static JsonNode readTree(String json) {
        return MAPPER.readTree(json);
    }

    /**
     * 解析 UTF-8 JSON 字节为 JsonNode 树。
     *
     * @param json JSON 字节
     * @return JSON 树
     */
    public static JsonNode readTree(byte[] json) {
        return MAPPER.readTree(json);
    }

    /**
     * 将 JSON 树转换为指定类型的对象。
     *
     * @param node JSON 树节点
     * @param type 目标类型
     * @param <T> 目标类型参数
     * @return 反序列化结果
     */
    public static <T> T treeToValue(JsonNode node, Class<T> type) {
        return MAPPER.treeToValue(node, type);
    }

    /**
     * 将任意对象转换为 JSON 树。
     *
     * @param value 待转换对象
     * @return JSON 树
     */
    public static JsonNode valueToTree(Object value) {
        return MAPPER.valueToTree(value);
    }

    /**
     * 读取对象字段的文本值，字段缺失或为 null 时返回 null。
     *
     * @param node JSON 对象节点
     * @param field 字段名
     * @return 文本值，可能为 null
     */
    public static String textOrNull(JsonNode node, String field) {
        JsonNode value = node.path(field);
        return value.isMissingNode() || value.isNull() ? null : value.asText();
    }
}
