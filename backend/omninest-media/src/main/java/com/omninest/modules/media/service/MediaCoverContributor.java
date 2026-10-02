package com.omninest.modules.media.service;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 媒体封面贡献者：由 music / video / reader 各业务域实现，向封面目录
 * 提供本域的源文件节点到封面文件节点解析结果。
 *
 * <p>接口定义在 media 包、实现类落在各业务包，使封面目录聚合器只依赖
 * 本包接口而不 import 业务 repository，保持 feature 依赖单向
 * （业务包 -&gt; media）。</p>
 *
 * @author OmniNest
 */
public interface MediaCoverContributor {

    /**
     * 解析本域的封面映射并写入输出收集器。
     *
     * @param ownerUserId 当前用户（媒体库归属过滤，仅 video 域使用）
     * @param fileNodeIds 待解析的源文件节点 ID 集合
     * @param covers 输出收集器：源文件 ID -&gt; 封面文件 ID
     */
    void contribute(UUID ownerUserId, List<UUID> fileNodeIds, Map<UUID, UUID> covers);
}
