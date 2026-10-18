package com.omninest.modules.file.dto;

import java.io.IOException;
import java.io.InputStream;
import java.util.Objects;

/**
 * 已完成权限校验的文件内容区间句柄。
 *
 * @param inputStream 区间内容流，长度不超过请求的区间字节数
 * @param totalBytes 对象完整字节数，与区间长度无关
 * @author OmniNest
 */
public record FileContentRange(
        InputStream inputStream,
        long totalBytes
) implements AutoCloseable {

    public FileContentRange {
        Objects.requireNonNull(inputStream, "inputStream");
    }

    @Override
    public void close() throws IOException {
        inputStream.close();
    }
}
