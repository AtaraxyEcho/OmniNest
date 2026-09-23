package com.omninest.modules.music.service;

import com.omninest.common.api.ApiResponse;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.Executor;
import java.util.function.Supplier;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;

/**
 * 在线音乐第三方读接口的异步派发。
 *
 * <p>控制器线程只负责鉴权、参数校验和取当前用户，外部平台的等待与解析放到音乐专用
 * 有界线程池执行，避免网易云侧变慢时占满通用请求线程，拖垮文件、认证等无关接口。
 * 登录、登出等写路径不经过这里，保持同步语义。</p>
 *
 * @author OmniNest
 */
@Component
public class MusicOnlineDispatcher {

    private final Executor executor;

    public MusicOnlineDispatcher(@Qualifier("musicOnlineExecutor") Executor executor) {
        this.executor = executor;
    }

    /**
     * 在音乐专用线程池上执行一次第三方读取并包装统一响应。
     *
     * @param call 读取逻辑，异常按原类型向上传播交给全局异常处理
     * @param <T> 响应数据类型
     * @return 完成后携带 {@link ApiResponse} 的 future
     */
    public <T> CompletableFuture<ApiResponse<T>> online(Supplier<T> call) {
        return CompletableFuture.supplyAsync(() -> ApiResponse.success(call.get()), executor);
    }
}
