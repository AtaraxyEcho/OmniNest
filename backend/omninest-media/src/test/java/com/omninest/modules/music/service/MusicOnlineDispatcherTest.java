package com.omninest.modules.music.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

/**
 * 在线音乐第三方读取的异步派发契约测试。
 *
 * @author OmniNest
 */
class MusicOnlineDispatcherTest {

    private final ExecutorService pool = Executors.newThreadPerTaskExecutor(
            Thread.ofPlatform().name("music-online-test-", 0).factory()
    );
    private final MusicOnlineDispatcher dispatcher = new MusicOnlineDispatcher(pool);

    @AfterEach
    void shutDownPool() {
        pool.shutdownNow();
    }

    @Test
    void thirdPartyReadRunsOffTheCallingThreadAndWrapsTheResult() throws Exception {
        String callerThread = Thread.currentThread().getName();

        CompletableFuture<ApiResponse<String>> future = dispatcher.online(
                () -> Thread.currentThread().getName()
        );
        ApiResponse<String> response = future.get(5, TimeUnit.SECONDS);

        assertThat(response.getData()).startsWith("music-online-test-");
        assertThat(response.getData()).isNotEqualTo(callerThread);
    }

    @Test
    void businessExceptionKeepsItsTypeForTheGlobalHandler() {
        CompletableFuture<ApiResponse<String>> future = dispatcher.online(() -> {
            throw new BusinessException(ErrorCode.DEPENDENCY_UNAVAILABLE, "平台接口不可用");
        });

        // 控制器侧的异常映射依赖原始业务异常类型可见，不能被替换成别的异常。
        assertThatThrownBy(future::join)
                .isInstanceOf(CompletionException.class)
                .hasCauseInstanceOf(BusinessException.class)
                .hasMessageContaining("平台接口不可用");
    }
}
