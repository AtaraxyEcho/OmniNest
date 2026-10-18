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

    /**
     * 判断一段字节在结构上是否是 BitTorrent 种子（顶层字典含 info，且 info 里有合法的分片表）。
     * 用于识别"直链指向的其实是种子"：这类内容需要先过 {@link #validate(byte[])} 才能交给下载器展开，
     * 不能仅凭文件扩展名判断。
     *
     * @param candidate 待判定的字节
     * @return 结构上是种子时为真
     */
    boolean looksLikeTorrent(byte[] candidate);
}
