package com.omninest.modules.file.dto;

import java.io.IOException;
import java.io.InputStream;
import java.util.Objects;

/**
 * 已完成权限校验的文件内容流句柄。
 *
 * @param inputStream 对象内容流
 * @param fileName 文件名
 * @param sizeBytes 文件字节数
 * @param mimeType 文件 MIME 类型
 * @author OmniNest
 */
public record FileContentStream(
        InputStream inputStream,
        String fileName,
        long sizeBytes,
        String mimeType
) implements AutoCloseable {

    public FileContentStream {
        Objects.requireNonNull(inputStream, "inputStream");
    }

    @Override
    public void close() throws IOException {
        inputStream.close();
    }
}
