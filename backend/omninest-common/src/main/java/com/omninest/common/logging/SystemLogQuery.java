package com.omninest.common.logging;

/**
 * 运行进程的有界日志查询端口。
 */
public interface SystemLogQuery {

    /**
     * 按消息、级别和记录器筛选最近日志。
     *
     * @param query 消息或来源包含的关键字
     * @param level 精确日志级别，空字符串表示全部
     * @param source 记录器名称包含的关键字
     * @param page 从零开始的页码
     * @param size 页面容量
     * @return 最新优先的筛选结果
     */
    SystemLogPage search(String query, String level, String source, int page, int size);
}
