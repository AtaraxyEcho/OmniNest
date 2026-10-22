package com.omninest.modules.task.support;

import java.util.regex.Pattern;

/**
 * 管理端任务文本脱敏。
 *
 * <p>任务载荷、结果与错误摘要可能包含用户私人空间的文件名或宿主机路径。
 * 管理员跨用户查看任务时只保留可诊断的部分，路径与文件名字段统一替换为占位符。</p>
 *
 * @author OmniNest
 */
public final class TaskSensitiveTextMasker {

    private static final String MASK = "[已脱敏]";
    private static final String MASK_PATH = "[已脱敏路径]";

    private static final Pattern FILE_FIELD = Pattern.compile(
            "(\"(?:filePath|targetPath|sourcePath|objectKey|fileName|name|path)\"\\s*:\\s*\")[^\"]*(\")");

    private static final Pattern URL = Pattern.compile("https?://[^\\s\"'<>]+");

    private static final Pattern WINDOWS_PATH = Pattern.compile("[A-Za-z]:[\\\\/][^\\s\"'<>|]+");

    private static final Pattern UNIX_PATH = Pattern.compile(
            "(?<![\\w:])/(?:[^/\\s\"'<>]+/)+[^/\\s\"'<>]+");

    private TaskSensitiveTextMasker() {
    }

    /**
     * 脱敏文本中的文件路径与文件名字段；null 原样返回。
     *
     * @param text 原始文本
     * @return 脱敏后的文本
     */
    public static String mask(String text) {
        if (text == null || text.isEmpty()) {
            return text;
        }
        String masked = FILE_FIELD.matcher(text).replaceAll("$1" + MASK + "$2");
        masked = URL.matcher(masked).replaceAll(MASK_PATH);
        masked = WINDOWS_PATH.matcher(masked).replaceAll(MASK_PATH);
        return UNIX_PATH.matcher(masked).replaceAll(MASK_PATH);
    }
}
