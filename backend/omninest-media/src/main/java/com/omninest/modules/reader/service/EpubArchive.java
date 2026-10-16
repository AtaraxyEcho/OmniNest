package com.omninest.modules.reader.service;

import java.io.Closeable;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * EPUB 文件的随机访问抽象。
 *
 * <p>EPUB 本质是 ZIP，但解析阶段只需要读取 OPF、nav、xhtml 等小文件，
 * 图片应按 entry 引用记录，不应全量加载。
 *
 * <p>使用 {@link ZipFile} 实现随机访问，避免将整个 EPUB 读入内存。
 *
 * @author OmniNest
 */
public class EpubArchive implements Closeable {

    private static final long MAX_SMALL_ENTRY_BYTES = 5L * 1024 * 1024;

    private final ZipFile zipFile;

    /**
     * 从文件路径打开 EPUB。
     *
     * @param path EPUB 文件的本地路径
     * @param safetyPolicy 压缩包安全策略
     * @throws IOException 文件不存在或不是有效 ZIP
     */
    public EpubArchive(Path path, ReaderArchiveSafetyPolicy safetyPolicy) throws IOException {
        safetyPolicy.validateArchiveSize(Files.size(path));
        this.zipFile = new ZipFile(path.toFile());
        try {
            safetyPolicy.validateZipFile(zipFile);
        } catch (RuntimeException exception) {
            try {
                zipFile.close();
            } catch (IOException closeException) {
                exception.addSuppressed(closeException);
            }
            throw exception;
        }
    }

    /**
     * 读取小文件为 UTF-8 字符串。
     * 适用于 OPF、nav.xhtml、toc.ncx、container.xml 等 XML/HTML 文件。
     *
     * @param entryPath ZIP 内的路径
     * @return 文件内容，未找到时返回 null
     */
    public String readSmallText(String entryPath) {
        byte[] bytes = readSmallBytes(entryPath);
        if (bytes == null) {
            return null;
        }
        return new String(bytes, StandardCharsets.UTF_8);
    }

    /**
     * 读取小文件为字节数组。
     * 适用于 OPF、XHTML、SVG 等小文件。不适用于大图片。
     *
     * @param entryPath ZIP 内的路径
     * @return 文件字节，未找到时返回 null
     */
    public byte[] readSmallBytes(String entryPath) {
        ZipEntry entry = zipFile.getEntry(entryPath);
        if (entry == null) {
            // 尝试大小写不敏感匹配
            entry = findEntryIgnoreCase(entryPath);
        }
        if (entry == null) {
            return null;
        }
        if (entry.getSize() > MAX_SMALL_ENTRY_BYTES) {
            return null;
        }

        try (InputStream is = zipFile.getInputStream(entry)) {
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int read;
            long totalRead = 0;
            while ((read = is.read(buffer)) != -1) {
                totalRead += read;
                if (totalRead > MAX_SMALL_ENTRY_BYTES) {
                    return null;
                }
                baos.write(buffer, 0, read);
            }
            return baos.toByteArray();
        } catch (IOException e) {
            return null;
        }
    }

    /**
     * 获取图片条目的头部字节（用于解析宽高）。
     *
     * @param entryPath 图片在 ZIP 内的路径
     * @param maxBytes  最大读取字节数
     * @return 头部字节，未找到时返回 null
     */
    public byte[] readImageHeader(String entryPath, int maxBytes) {
        ZipEntry entry = zipFile.getEntry(entryPath);
        if (entry == null) {
            entry = findEntryIgnoreCase(entryPath);
        }
        if (entry == null) {
            return null;
        }

        try (InputStream is = zipFile.getInputStream(entry)) {
            byte[] header = new byte[maxBytes];
            int totalRead = 0;
            while (totalRead < maxBytes) {
                int bytesRead = is.read(header, totalRead, maxBytes - totalRead);
                if (bytesRead == -1) {
                    break;
                }
                totalRead += bytesRead;
            }
            if (totalRead < header.length) {
                byte[] trimmed = new byte[totalRead];
                System.arraycopy(header, 0, trimmed, 0, totalRead);
                return trimmed;
            }
            return header;
        } catch (IOException e) {
            return null;
        }
    }

    /**
     * 打开图片条目的输入流（用于按需读取完整图片）。
     *
     * @param entryPath 图片在 ZIP 内的路径
     * @return 输入流，未找到时返回 null
     */
    public InputStream openEntryStream(String entryPath) {
        ZipEntry entry = zipFile.getEntry(entryPath);
        if (entry == null) {
            entry = findEntryIgnoreCase(entryPath);
        }
        if (entry == null) {
            return null;
        }

        try {
            return zipFile.getInputStream(entry);
        } catch (IOException e) {
            return null;
        }
    }

    /**
     * 获取条目的大小。
     *
     * @param entryPath ZIP 内的路径
     * @return 条目大小，未找到时返回 -1
     */
    public long getEntrySize(String entryPath) {
        ZipEntry entry = zipFile.getEntry(entryPath);
        if (entry == null) {
            entry = findEntryIgnoreCase(entryPath);
        }
        return entry != null ? entry.getSize() : -1;
    }

    /**
     * 获取条目的 CRC-32。
     *
     * @param entryPath ZIP 内的路径
     * @return CRC-32 值，未找到时返回 -1
     */
    public long getEntryCrc(String entryPath) {
        ZipEntry entry = zipFile.getEntry(entryPath);
        if (entry == null) {
            entry = findEntryIgnoreCase(entryPath);
        }
        return entry != null ? entry.getCrc() : -1;
    }

    /**
     * 解析路径在压缩包内的真实条目名（含大小写不敏感回退）。
     *
     * <p>OPF/XHTML 里声明的 href 可能与真实条目名大小写不一致，读取侧每个入口都会
     * 回退匹配一次；但漫画页面是按名字存进库的，按需流式解压只有精确的条目名才命中，
     * 所以草稿必须存真实条目名而不是声明路径。
     *
     * @param entryPath 声明的相对路径
     * @return 真实条目名；条目不存在时返回 null
     */
    public String resolveEntryName(String entryPath) {
        if (entryPath == null || entryPath.isBlank()) {
            return null;
        }
        ZipEntry entry = zipFile.getEntry(entryPath);
        if (entry == null) {
            entry = findEntryIgnoreCase(entryPath);
        }
        return entry != null ? entry.getName() : null;
    }

    /**
     * 大小写不敏感查找条目。
     * EPUB 内部路径可能与 OPF manifest 中声明的 href 大小写不一致。
     */
    private ZipEntry findEntryIgnoreCase(String path) {
        String lower = path.toLowerCase(Locale.ROOT);
        var entries = zipFile.entries();
        while (entries.hasMoreElements()) {
            ZipEntry e = entries.nextElement();
            if (e.getName().toLowerCase(Locale.ROOT).equals(lower)) {
                return e;
            }
        }
        return null;
    }

    /**
     * 枚举压缩包内全部条目名。
     *
     * @return 条目名列表
     */
    public List<String> entryNames() {
        List<String> names = new ArrayList<>();
        var entries = zipFile.entries();
        while (entries.hasMoreElements()) {
            names.add(entries.nextElement().getName());
        }
        return names;
    }

    @Override
    public void close() throws IOException {
        if (zipFile != null) {
            zipFile.close();
        }
    }
}
