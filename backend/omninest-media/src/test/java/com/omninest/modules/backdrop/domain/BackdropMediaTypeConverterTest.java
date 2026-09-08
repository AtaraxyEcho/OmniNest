package com.omninest.modules.backdrop.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class BackdropMediaTypeConverterTest {

    private final BackdropMediaTypeConverter converter = new BackdropMediaTypeConverter();

    @Test
    void mapsEnumToLowercaseStoredValue() {
        assertThat(converter.convertToDatabaseColumn(BackdropMediaType.IMAGE)).isEqualTo("image");
        assertThat(converter.convertToDatabaseColumn(BackdropMediaType.GIF)).isEqualTo("gif");
        assertThat(converter.convertToDatabaseColumn(BackdropMediaType.VIDEO)).isEqualTo("video");
        assertThat(converter.convertToDatabaseColumn(null)).isNull();
    }

    @Test
    void mapsStoredValueToEnum() {
        assertThat(converter.convertToEntityAttribute("image")).isEqualTo(BackdropMediaType.IMAGE);
        assertThat(converter.convertToEntityAttribute("gif")).isEqualTo(BackdropMediaType.GIF);
        assertThat(converter.convertToEntityAttribute("video")).isEqualTo(BackdropMediaType.VIDEO);
        assertThat(converter.convertToEntityAttribute(null)).isNull();
    }

    @Test
    void fallsBackToImageOnUnknownStoredValue() {
        assertThat(converter.convertToEntityAttribute("movie")).isEqualTo(BackdropMediaType.IMAGE);
    }
}
