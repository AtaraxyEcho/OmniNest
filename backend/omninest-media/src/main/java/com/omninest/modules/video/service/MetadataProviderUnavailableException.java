package com.omninest.modules.video.service;

/**
 * 元数据提供器不可达：连接超时、DNS 或 TLS 失败等传输层故障。
 *
 * <p>与「搜索无结果」区分：空列表是提供器正常应答，本异常表示没拿到应答。</p>
 *
 * @author OmniNest
 */
public class MetadataProviderUnavailableException extends RuntimeException {

    private final String providerName;

    public MetadataProviderUnavailableException(String providerName, String message, Throwable cause) {
        super(message, cause);
        this.providerName = providerName;
    }

    /** 提供器名称，用于拼接面向用户的提示。 */
    public String providerName() {
        return providerName;
    }
}
