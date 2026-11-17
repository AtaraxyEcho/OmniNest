package com.omninest.common.processing;

import java.nio.file.Path;

/**
 * 业务临时文件暂存端口。
 *
 * <p>媒体派生、封面、转码等处理只允许经本端口在配置的处理根目录下
 * 创建/删除自有临时文件，禁止直接使用系统临时目录或用户内容路径。</p>
 *
 * @author OmniNest
 */
public interface TempStagingPort {

    /**
     * 在指定业务子目录下创建临时文件。
     *
     * @param segment 业务子目录名，例如 music-cover 或 transcode
     * @param prefix 文件名前缀
     * @param suffix 文件名后缀，含点号
     * @return 已创建的临时文件路径
     */
    Path createTempFile(String segment, String prefix, String suffix);

    /**
     * 解析并确保存在业务子目录。
     *
     * @param segment 业务子目录名
     * @return 可用目录
     */
    Path ensureDirectory(String segment);

    /**
     * 尽力删除临时文件或目录，失败只记录不抛出。
     *
     * @param path 待删除路径
     */
    void deleteQuietly(Path path);
}
