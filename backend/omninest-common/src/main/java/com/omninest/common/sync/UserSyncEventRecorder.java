package com.omninest.common.sync;

import java.util.List;
import java.util.UUID;

/**
 * 业务模块记录用户同步事件的公共接口。
 *
 * @author OmniNest
 */
public interface UserSyncEventRecorder {

    /**
     * 在当前业务事务中记录同步事件。
     *
     * @param command 同步事件命令
     * @return 事件标识
     */
    UUID record(SyncEventCommand command);

    /**
     * 在当前业务事务中批量记录同步事件。
     *
     * <p>广播型事件（管理审计推给所有有读权限的用户）收件人数量与用户规模同阶，
     * 逐条 {@link #record} 会变成 N 次 insert。默认实现保持逐条语义，实现类应覆写
     * 成一次批量写入。</p>
     *
     * @param commands 同步事件命令
     * @return 事件标识，顺序与入参一致
     */
    default List<UUID> recordAll(List<SyncEventCommand> commands) {
        return commands.stream().map(this::record).toList();
    }
}
