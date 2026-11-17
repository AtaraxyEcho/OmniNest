package com.omninest.modules.file.service;

import java.util.List;

/**
 * 业务模块参与文件永久删除的扩展点。
 *
 * @author OmniNest
 */
public interface FilePurgeParticipant {
    /**
     * 查询目标文件节点的业务引用。
     *
     * @param context 删除上下文
     * @return 业务引用
     */
    default List<FileBusinessReference> findBusinessReferences(PurgeContext context) {
        return List.of();
    }


    /**
     * 分页贡献业务模块持有的派生文件节点。
     *
     * @param context 删除上下文
     * @param writer 贡献写入器
     */
    void contribute(PurgeContext context, PurgeContributionWriter writer);

    /**
     * 对象删除完成后幂等清理业务数据库记录。
     *
     * @param context 删除上下文
     */
    void finalizePurge(PurgeContext context);
}
