package com.omninest.common.download;

/**
 * 校验种子文件内嵌的对外地址，供离线下载在提交给下载器之前调用。
 *
 * @author OmniNest
 */
public interface TorrentAddressValidator {

    /**
     * 解析种子并校验其中会触发对外请求的字段，不合法时抛出业务异常。
     *
     * @param torrentBytes 种子文件字节
     */
    void validate(byte[] torrentBytes);
}
