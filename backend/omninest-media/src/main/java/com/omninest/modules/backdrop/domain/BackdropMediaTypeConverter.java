package com.omninest.modules.backdrop.domain;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;

/**
 * 背景素材媒体类型与持久化值的转换器。
 * 数据库存值与前端序列化值一致，为小写 image / gif / video。
 *
 * @author OmniNest
 */
@Converter
public class BackdropMediaTypeConverter implements AttributeConverter<BackdropMediaType, String> {

    @Override
    public String convertToDatabaseColumn(BackdropMediaType attribute) {
        return attribute == null ? null : attribute.getValue();
    }

    @Override
    public BackdropMediaType convertToEntityAttribute(String dbData) {
        return dbData == null ? null : BackdropMediaType.fromValue(dbData);
    }
}
