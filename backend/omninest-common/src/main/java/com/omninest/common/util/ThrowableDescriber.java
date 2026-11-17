package com.omninest.common.util;

import com.omninest.common.error.StackSummaries;
import java.io.PrintWriter;
import java.io.StringWriter;

/**
 * 将异常压缩为可入库的堆栈摘要。
 *
 * <p>取根因异常，保留类型、消息与栈顶帧，超长截断；堆栈帧仅含类名与
 * 位置，不包含运行时参数值，避免敏感数据进入任务表。</p>
 *
 * @author OmniNest
 */
public final class ThrowableDescriber {

    private static final int MAX_LENGTH = 8192;
    private static final int MAX_FRAMES = 20;

    private ThrowableDescriber() {
    }

    /**
     * 生成异常堆栈摘要。
     *
     * @param throwable 原始异常，可为 null
     * @return 脱敏截断后的堆栈摘要；入参为 null 时返回 null
     */
    public static String describe(Throwable throwable) {
        if (throwable == null) {
            return null;
        }
        Throwable root = throwable;
        while (root.getCause() != null && root.getCause() != root) {
            root = root.getCause();
        }
        StringWriter buffer = new StringWriter(512);
        PrintWriter writer = new PrintWriter(buffer);
        writer.println(root.getClass().getName() + ": " + root.getMessage());
        StackTraceElement[] frames = root.getStackTrace();
        int frameLimit = Math.min(frames.length, MAX_FRAMES);
        for (int i = 0; i < frameLimit; i++) {
            writer.println("\tat " + frames[i]);
        }
        if (frames.length > frameLimit) {
            writer.println("\t... " + (frames.length - frameLimit) + " more");
        }
        writer.flush();
        // 根因消息原样包含 SQL 约束名、MinIO 内网端点与本地绝对路径，
        // 落库前必须与堆栈一起脱敏（任务详情会回显给前端）。
        String summary = StackSummaries.redact(buffer.toString());
        if (summary.length() > MAX_LENGTH) {
            return summary.substring(0, MAX_LENGTH);
        }
        return summary;
    }
}
