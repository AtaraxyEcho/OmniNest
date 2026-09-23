package com.omninest.app.music;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.error.GlobalExceptionHandler;
import java.util.concurrent.CompletableFuture;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 异步返回值的异常映射契约测试。
 *
 * <p>音乐在线接口把第三方等待放到 {@link CompletableFuture} 上返回，全局异常处理必须仍按
 * 原业务异常类型映射状态码；若异步完成时的异常被包成 {@code CompletionException} 交给
 * 解析器，业务错误会退化成 500，前端拿不到稳定错误码。</p>
 */
class OnlineAsyncReturnContractTest {

    private final MockMvc mockMvc = MockMvcBuilders
            .standaloneSetup(new ProbeController())
            .setControllerAdvice(new GlobalExceptionHandler())
            .build();

    @Test
    void asyncFailureStillMapsToTheBusinessStatusCode() throws Exception {
        MvcResult started = mockMvc.perform(get("/probe/async-business-error")).andReturn();
        assertThat(started.getRequest().isAsyncStarted()).isTrue();

        mockMvc.perform(MockMvcRequestBuilders.asyncDispatch(started))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.code").value(ErrorCode.DEPENDENCY_UNAVAILABLE.getCode()));
    }

    @Test
    void asyncSuccessBodyIsUnwrapped() throws Exception {
        MvcResult started = mockMvc.perform(get("/probe/async-success")).andReturn();
        assertThat(started.getRequest().isAsyncStarted()).isTrue();

        mockMvc.perform(MockMvcRequestBuilders.asyncDispatch(started))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data").value("done"));
    }

    @RestController
    static class ProbeController {

        @GetMapping("/probe/async-business-error")
        CompletableFuture<ApiResponse<String>> businessError() {
            return CompletableFuture.supplyAsync(() -> {
                throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "平台接口不可用");
            });
        }

        @GetMapping("/probe/async-success")
        CompletableFuture<ApiResponse<String>> success() {
            return CompletableFuture.completedFuture(ApiResponse.success("done"));
        }
    }
}
