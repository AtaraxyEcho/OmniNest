package com.omninest.modules.file.port;

import java.util.Collection;
import java.util.Map;
import java.util.UUID;

/**
 * 媒体封面反查端口：按源文件节点 ID 批量解析其媒体库封面文件节点 ID。
 *
 * <p>封面数据由 music / video / reader 三个域持有（曲目的
 * coverFileId、影片与季的 posterFileId、阅读条目的 coverFileId），
 * 均以文件节点形态存放。实现方负责差异化 TTL 缓存：正结果长缓存、
 * 负结果短缓存，避免媒体入库前后的时序空窗被长期占位。</p>
 *
 * @author OmniNest
 */
public interface MediaCoverDirectory {

    /**
     * 批量解析源文件节点到封面文件节点。
     *
     * @param ownerUserId 当前用户（媒体库归属过滤）
     * @param fileNodeIds 源文件节点 ID 集合
     * @return 源文件 ID -&gt; 封面文件 ID；无封面或未知文件不出现在结果中
     */
    Map<UUID, UUID> resolveCoverFileIds(UUID ownerUserId, Collection<UUID> fileNodeIds);
}
