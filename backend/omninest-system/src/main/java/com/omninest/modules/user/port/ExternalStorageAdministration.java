package com.omninest.modules.user.port;

import java.util.List;
import java.util.UUID;

/**
 * 外部存储账户管理端口。
 *
 * @author OmniNest
 */
public interface ExternalStorageAdministration {

    /**
     * 统计外部存储账户数量。
     *
     * @return 外部存储账户数量
     */
    long countAccounts();

    /**
     * 按最近更新时间查询全部外部存储账户。
     *
     * @return 外部存储账户摘要列表
     */
    List<ExternalStorageAccountSummary> listAccounts();

    /**
     * 更新外部存储账户状态。
     *
     * @param accountId 账户标识
     * @param status 目标状态
     * @return 更新后的账户摘要
     */
    ExternalStorageAccountSummary updateStatus(UUID accountId, String status);
}
