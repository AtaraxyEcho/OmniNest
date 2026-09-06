package com.omninest.modules.photos.service;

import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;

/**
 * 三星 SEF（Samsung Extended Format）动态照片 trailer 扫描器。
 *
 * <p>SEF trailer 紧跟在 JPEG EOI 之后，以固定 footer 魔数 "SEFT" 结尾。
 * 扫描文件尾部有限窗口即可低成本识别，不解析私有记录结构。</p>
 *
 * @author OmniNest
 */
public final class PhotoMotionTrailerScanner {

    /** 尾部扫描窗口大小；SEF footer 固定在文件末尾，4KB 足够。 */
    public static final int TAIL_WINDOW_BYTES = 4096;

    private static final byte[] SEF_FOOTER = "SEFT".getBytes(StandardCharsets.US_ASCII);

    private PhotoMotionTrailerScanner() {
    }

    /**
     * 在尾部缓冲中扫描 SEF footer 魔数。
     *
     * @param tail 尾部字节缓冲
     * @param validLength 缓冲中的有效字节数
     * @return 命中返回 true
     */
    public static boolean hasSefTrailer(byte[] tail, int validLength) {
        if (tail == null || validLength < SEF_FOOTER.length) {
            return false;
        }
        int limit = validLength - SEF_FOOTER.length;
        for (int i = 0; i <= limit; i++) {
            boolean matched = true;
            for (int j = 0; j < SEF_FOOTER.length; j++) {
                if (tail[i + j] != SEF_FOOTER[j]) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                return true;
            }
        }
        return false;
    }

    /**
     * 直接扫描文件尾部的 SEF footer 魔数。
     *
     * @param sourceFile 源文件
     * @return 命中返回 true；文件读取失败返回 false
     */
    public static boolean scanTail(Path sourceFile) {
        try (RandomAccessFile file = new RandomAccessFile(sourceFile.toFile(), "r")) {
            long size = file.length();
            int window = (int) Math.min(TAIL_WINDOW_BYTES, size);
            if (window < SEF_FOOTER.length) {
                return false;
            }
            byte[] tail = new byte[window];
            file.seek(size - window);
            file.readFully(tail);
            return hasSefTrailer(tail, window);
        } catch (IOException ex) {
            return false;
        }
    }
}
