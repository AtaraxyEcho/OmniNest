package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.util.Locale;
import java.util.Set;

/**
 * 外部存储 Provider 白名单。禁止 LOCAL；未实现完整语义的类型不得放行。
 *
 * @author OmniNest
 */
public final class ExternalStorageProviders {

    private static final Set<String> ALLOWED = Set.of(
            "S3",
            "MINIO",
            "WEBDAV",
            "ONEDRIVE",
            "GDRIVE",
            "GOOGLE_DRIVE",
            "ALIYUN_DRIVE",
            "DROPBOX",
            "QUARK",
            "BAIDU"
    );

    private ExternalStorageProviders() {
    }

    /**
     * 规范化并校验 Provider 编码。
     *
     * @param provider 客户端提交的 Provider
     * @return 大写规范化编码
     */
    public static String requireAllowed(String provider) {
        if (provider == null || provider.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "外部存储类型不能为空");
        }
        String normalized = provider.trim().toUpperCase(Locale.ROOT);
        if ("LOCAL".equals(normalized) || "SMB".equals(normalized)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "该外部存储类型已停用，请使用本地媒体位置或其它远程类型");
        }
        if (!ALLOWED.contains(normalized)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "不支持的外部存储类型");
        }
        return normalized;
    }
}
