package com.omninest.common.api;

import com.omninest.common.enums.ErrorCode;
import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * 统一 API 响应体。
 *
 * @param <T> 响应数据类型
 */
@Schema(description = "统一 API 响应体")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ApiResponse<T> {
    @Schema(description = "业务状态码", example = "0")
    private Integer code;
    @Schema(description = "响应消息", example = "success")
    private String message;
    @Schema(description = "响应数据")
    private T data;
    @Schema(description = "错误详情")
    private Object details;
    @Schema(description = "稳定错误名（ErrorCode 枚举名），供客户端本地化")
    private String errorName;

    public ApiResponse(Integer code, String message, T data) {
        this.code = code;
        this.message = message;
        this.data = data;
        this.details = null;
        this.errorName = null;
    }

    public static <T> ApiResponse<T> success() {
        return new ApiResponse<>(ErrorCode.SUCCESS.getCode(), ErrorCode.SUCCESS.getMessage(), null);
    }

    public static <T> ApiResponse<T> success(T data) {
        return new ApiResponse<>(ErrorCode.SUCCESS.getCode(), ErrorCode.SUCCESS.getMessage(), data);
    }

    public static <T> ApiResponse<T> success(String message, T data) {
        return new ApiResponse<>(200, message, data);
    }

    public static <T> ApiResponse<T> error(Integer code, String message) {
        return new ApiResponse<>(code, message, null);
    }

    public static <T> ApiResponse<T> error(ErrorCode errorCode) {
        ApiResponse<T> response = new ApiResponse<>(errorCode.getCode(), errorCode.getMessage(), null);
        response.setErrorName(errorCode.name());
        return response;
    }

    public static <T> ApiResponse<T> error(ErrorCode errorCode, String customMessage) {
        ApiResponse<T> response = new ApiResponse<>(errorCode.getCode(), customMessage, null);
        response.setErrorName(errorCode.name());
        return response;
    }

    public static <T> ApiResponse<T> error(ErrorCode errorCode, String customMessage, Object details) {
        ApiResponse<T> response = new ApiResponse<>(errorCode.getCode(), customMessage, null);
        response.setDetails(details);
        response.setErrorName(errorCode.name());
        return response;
    }
}
