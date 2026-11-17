package com.omninest.modules.weather.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/**
 * 用户位置上报请求
 *
 * @param latitude  纬度（-90 ~ 90）
 * @param longitude 经度（-180 ~ 180）
 * @param source    来源：mobile / desktop / web
 */
public record UserLocationDto(
        @NotNull @Min(-90) @Max(90) Double latitude,
        @NotNull @Min(-180) @Max(180) Double longitude,
        @NotBlank String source
) {
}
