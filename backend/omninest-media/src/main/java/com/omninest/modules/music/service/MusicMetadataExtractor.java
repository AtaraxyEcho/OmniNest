package com.omninest.modules.music.service;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 音频元数据提取器，支持 ID3v2（MP3/WAV）、FLAC、OGG、M4A/AAC、WAV（RIFF INFO）。
 */
@Slf4j
@Component
public class MusicMetadataExtractor {
    private static final int MAX_TAG_BYTES = 8 * 1024 * 1024;

    public Metadata extract(InputStream inputStream, String fileName, String mimeType) throws IOException {
        return extract(inputStream, fileName, mimeType, 0L);
    }

    /**
     * 提取音频元数据。
     *
     * @param inputStream 音频内容流，只读取前 {@value #MAX_TAG_BYTES} 字节
     * @param fileName 文件名，仅用于日志与无标签兜底
     * @param mimeType 声明的 MIME 类型
     * @param fileSizeBytes 音频总字节数，用于恒定码率 MP3 的时长估算；0 表示未知
     * @return 解析出的元数据，未识别容器时为空值
     * @throws IOException 内容读取失败
     */
    public Metadata extract(
            InputStream inputStream,
            String fileName,
            String mimeType,
            long fileSizeBytes
    ) throws IOException {
        log.debug("提取音乐元数据: fileName={}", fileName);
        byte[] bytes = inputStream.readNBytes(MAX_TAG_BYTES);
        if (bytes.length < 4) {
            return Metadata.empty();
        }
        // 按 magic bytes 分发到对应解析器
        if (bytes[0] == 'I' && bytes[1] == 'D' && bytes[2] == '3') {
            return parseId3v2(bytes, fileName, fileSizeBytes);
        }
        if (bytes[0] == 'f' && bytes[1] == 'L' && bytes[2] == 'a' && bytes[3] == 'C') {
            return parseFlac(bytes, fileName);
        }
        if (bytes[0] == 'O' && bytes[1] == 'g' && bytes[2] == 'g' && bytes[3] == 'S') {
            return parseOgg(bytes, fileName);
        }
        // M4A/AAC: ftyp atom (offset 4 = "ftyp" 或 "ftypM4A " 等)
        if (bytes.length >= 8 && bytes[4] == 'f' && bytes[5] == 't' && bytes[6] == 'y' && bytes[7] == 'p') {
            return parseMp4Ilst(bytes, fileName);
        }
        // WAV: RIFF....WAVE
        if (bytes[0] == 'R' && bytes[1] == 'I' && bytes[2] == 'F' && bytes[3] == 'F'
                && bytes.length >= 12 && bytes[8] == 'W' && bytes[9] == 'A' && bytes[10] == 'V' && bytes[11] == 'E') {
            return parseWav(bytes, fileName, fileSizeBytes);
        }
        // 兜底：某些 MP3 文件在 ID3 标签之前有垃圾数据，尝试在前 4KB 内搜索 ID3
        Metadata id3Fallback = searchId3v2(bytes, Math.min(bytes.length, 4096), fileName, fileSizeBytes);
        if (id3Fallback != null) {
            return id3Fallback;
        }
        log.debug("未识别的音频格式: fileName={}", fileName);
        return Metadata.empty();
    }

    // ─── ID3v2（MP3 / 嵌入 ID3 的 WAV）────────────────────────────────────

    private Metadata parseId3v2(byte[] bytes, String fileName, long fileSizeBytes) {
        int majorVersion = bytes[3] & 0xFF;
        int tagSize = synchsafeInt(bytes, 6);
        int tagEnd = Math.min(bytes.length, 10 + tagSize);
        MutableMetadata metadata = new MutableMetadata();
        int offset = 10;
        while (offset + 10 <= tagEnd) {
            String frameId = new String(bytes, offset, 4, StandardCharsets.ISO_8859_1);
            if (frameId.chars().allMatch(value -> value == 0)) {
                break;
            }
            int frameSize = majorVersion == 4 ? synchsafeInt(bytes, offset + 4) : int32(bytes, offset + 4);
            if (frameSize <= 0 || offset + 10 + frameSize > tagEnd) {
                break;
            }
            byte[] frame = Arrays.copyOfRange(bytes, offset + 10, offset + 10 + frameSize);
            try {
                applyId3Frame(metadata, frameId, frame);
            } catch (RuntimeException e) {
                log.warn("ID3 解析异常: frameId={}, fileName={}", frameId, fileName, e);
            }
            offset += 10 + frameSize;
        }
        // 从 ID3 标签之后的 MPEG 帧头提取 bitrate、sampleRate 与时长
        parseMp3FrameHeader(bytes, tagEnd, metadata, fileSizeBytes);
        return metadata.toMetadata();
    }

    private void applyId3Frame(MutableMetadata metadata, String frameId, byte[] frame) {
        switch (frameId) {
            case "TIT2" -> metadata.title = decodeId3TextFrame(frame);
            case "TPE1" -> metadata.artistName = decodeId3TextFrame(frame);
            case "TALB" -> metadata.albumTitle = decodeId3TextFrame(frame);
            case "TCON" -> metadata.genre = decodeId3TextFrame(frame);
            case "TRCK" -> metadata.trackNumber = decodeId3TextFrame(frame);
            case "TPOS" -> metadata.discNumber = decodeId3TextFrame(frame);
            case "TLEN" -> metadata.durationSeconds = parsePositiveInt(decodeId3TextFrame(frame));
            case "USLT" -> metadata.lyricsRaw = decodeId3UnsynchronizedLyrics(frame);
            case "APIC" -> metadata.coverDataUrl = decodeId3AttachedPicture(frame);
            default -> { }
        }
    }

    /**
     * 解析 ID3 标签之后的第一个 MPEG 帧头，提取 bitrate、sampleRate 与时长。
     * MP3 帧头: 4 bytes, 同步字 0xFFE0。时长优先用 Xing/Info 帧数（VBR 精确），
     * 缺失时按恒定码率用总字节估算；两者都拿不到时留空。
     */
    private void parseMp3FrameHeader(
            byte[] bytes,
            int searchFrom,
            MutableMetadata metadata,
            long fileSizeBytes
    ) {
        // MPEG1 Layer3 bitrate 表 (index 1-14)
        int[] mp3Bitrates = {0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320};
        // MPEG1 sampleRate 表 (index 0-2)
        int[] mp3SampleRates = {44100, 48000, 32000};

        // 限制扫描范围为 ID3 标签后 32KB，避免非 MP3 文件全量扫描 8MB
        int searchEnd = Math.min(bytes.length, searchFrom + 32 * 1024);
        for (int i = searchFrom; i + 4 <= searchEnd; i++) {
            // 同步字: 11 1111 1111 1110 (0xFFE0)
            if ((bytes[i] & 0xFF) == 0xFF && (bytes[i + 1] & 0xE0) == 0xE0) {
                int header = ((bytes[i] & 0xFF) << 24)
                        | ((bytes[i + 1] & 0xFF) << 16)
                        | ((bytes[i + 2] & 0xFF) << 8)
                        | (bytes[i + 3] & 0xFF);
                int versionBits = (header >> 19) & 0x3;     // MPEG version
                int layerBits = (header >> 17) & 0x3;       // Layer
                int bitrateIndex = (header >> 12) & 0xF;    // bitrate index
                int sampleRateIndex = (header >> 10) & 0x3; // sampleRate index
                int padding = (header >> 9) & 1;

                // 只处理 MPEG1 Layer3 (version=3, layer=1)
                if (versionBits == 3 && layerBits == 1
                        && bitrateIndex > 0 && bitrateIndex < 15
                        && sampleRateIndex < 3) {
                    int bitrate = mp3Bitrates[bitrateIndex];
                    int sampleRate = mp3SampleRates[sampleRateIndex];
                    metadata.bitrate = bitrate;
                    metadata.sampleRate = sampleRate;
                    int frameLength = (144 * bitrate * 1000) / sampleRate + padding * 4;
                    metadata.durationSeconds = resolveMp3Duration(
                            bytes, i, frameLength, bitrate, sampleRate, searchFrom, fileSizeBytes);
                }
                return;
            }
        }
    }

    /**
     * Xing/Info 帧数优先，其次按恒定码率用音频字节数估算。
     */
    private Integer resolveMp3Duration(
            byte[] bytes,
            int frameStart,
            int frameLength,
            int bitrate,
            int sampleRate,
            int audioStart,
            long fileSizeBytes
    ) {
        int frames = findXingFrameCount(bytes, frameStart, frameLength);
        if (frames > 0 && sampleRate > 0) {
            // MPEG1 Layer3 每帧 1152 个采样。
            return (int) ((long) frames * 1152 / sampleRate);
        }
        long audioBytes = fileSizeBytes - audioStart;
        if (audioBytes > 0 && bitrate > 0) {
            return (int) (audioBytes * 8L / (bitrate * 1000L));
        }
        return null;
    }

    /**
     * 在首帧侧信息区查找 Xing/Info 标志并取帧数（flags 第 0 位表示带帧数）。
     */
    private int findXingFrameCount(byte[] bytes, int frameStart, int frameLength) {
        if (frameLength <= 0) {
            return 0;
        }
        int scanFrom = frameStart + 4;
        int scanTo = Math.min(bytes.length, frameStart + frameLength);
        for (int pos = scanFrom; pos + 12 <= scanTo; pos++) {
            boolean xing = bytes[pos] == 'X' && bytes[pos + 1] == 'i'
                    && bytes[pos + 2] == 'n' && bytes[pos + 3] == 'g';
            boolean info = bytes[pos] == 'I' && bytes[pos + 1] == 'n'
                    && bytes[pos + 2] == 'f' && bytes[pos + 3] == 'o';
            if (!xing && !info) {
                continue;
            }
            int flags = int32BE(bytes, pos + 4);
            return (flags & 1) == 1 ? int32BE(bytes, pos + 8) : 0;
        }
        return 0;
    }

    /**
     * 在字节范围内搜索 ID3 标签（兜底处理含前置垃圾数据的 MP3）。
     */
    private Metadata searchId3v2(byte[] bytes, int searchEnd, String fileName, long fileSizeBytes) {
        for (int i = 0; i + 10 <= searchEnd; i++) {
            if (bytes[i] == 'I' && bytes[i + 1] == 'D' && bytes[i + 2] == '3') {
                byte[] shifted = Arrays.copyOfRange(bytes, i, bytes.length);
                // 前置垃圾数据不计入音频长度，估算误差按一个标签量级处理。
                return parseId3v2(shifted, fileName, fileSizeBytes - i);
            }
        }
        return null;
    }

    // ─── FLAC（Vorbis Comments in FLAC metadata blocks）────────────────────

    private Metadata parseFlac(byte[] bytes, String fileName) {
        // FLAC 结构: 4 bytes "fLaC" + metadata blocks
        int offset = 4;
        MutableMetadata metadata = new MutableMetadata();
        while (offset + 4 <= bytes.length) {
            int header = int32BE(bytes, offset);
            boolean isLast = (header & 0x80000000) != 0;
            int blockType = (header >> 24) & 0x7F;
            int blockLength = header & 0x00FFFFFF;
            offset += 4;
            if (offset + blockLength > bytes.length) {
                break;
            }
            if (blockType == 0 && blockLength >= 18) {
                // STREAMINFO: sampleRate 占第 68-87 位，总采样数占第 108-143 位。
                int sampleRate = (int) readBitsBE(bytes, (offset * 8L) + 68, 20);
                long totalSamples = readBitsBE(bytes, (offset * 8L) + 108, 36);
                if (sampleRate > 0) {
                    metadata.sampleRate = sampleRate;
                }
                if (sampleRate > 0 && totalSamples > 0) {
                    metadata.durationSeconds = (int) (totalSamples / sampleRate);
                }
            }
            if (blockType == 4) {
                // VORBIS_COMMENT block
                parseVorbisComment(bytes, offset, blockLength, metadata);
            }
            if (blockType == 6) {
                // PICTURE block (FLAC native picture)
                if (metadata.coverDataUrl == null) {
                    metadata.coverDataUrl = decodeFlacPicture(bytes, offset, blockLength);
                }
            }
            offset += blockLength;
            if (isLast) {
                break;
            }
        }
        return metadata.toMetadata();
    }

    // ─── OGG（Vorbis / Opus）───────────────────────────────────────────────

    private Metadata parseOgg(byte[] bytes, String fileName) {
        // OGG 容器: 查找 Vorbis Comment header packet
        // Vorbis: 第 2 个 packet 的前 7 bytes = 03 + "vorbis"
        // Opus:   第 2 个 packet 的前 8 bytes = "OpusTags"
        MutableMetadata metadata = new MutableMetadata();

        // 搜索 Vorbis 标识
        for (int i = 0; i + 14 < bytes.length; i++) {
            // Vorbis Comment header: 0x03 + "vorbis"
            if (bytes[i] == 0x03 && bytes[i + 1] == 'v' && bytes[i + 2] == 'o' && bytes[i + 3] == 'r'
                    && bytes[i + 4] == 'b' && bytes[i + 5] == 'i' && bytes[i + 6] == 's') {
                parseVorbisComment(bytes, i + 7, bytes.length - i - 7, metadata);
                break;
            }
            // Opus Tags header: "OpusTags"
            if (bytes[i] == 'O' && bytes[i + 1] == 'p' && bytes[i + 2] == 'u' && bytes[i + 3] == 's'
                    && bytes[i + 4] == 'T' && bytes[i + 5] == 'a' && bytes[i + 6] == 'g' && bytes[i + 7] == 's') {
                parseVorbisComment(bytes, i + 8, bytes.length - i - 8, metadata);
                break;
            }
        }

        // OGG 容器中的封面：查找 METADATA_BLOCK_PICTURE（Vorbis spec）
        if (metadata.coverDataUrl == null) {
            for (int i = 0; i + 4 < bytes.length; i++) {
                if (bytes[i] == (byte) 0x80 && bytes[i + 1] == 'i' && bytes[i + 2] == 'm' && bytes[i + 3] == 'a'
                        && bytes[i + 4] == 'g' && bytes[i + 5] == 'e' && bytes[i + 6] == '/') {
                    // 后面跟 4 bytes type + 4 bytes mime length + mime + ...
                    metadata.coverDataUrl = decodeVorbisPicture(bytes, i + 7);
                    break;
                }
            }
        }
        return metadata.toMetadata();
    }

    // ─── Vorbis Comments 解析（FLAC / OGG 通用）────────────────────────────

    /**
     * 解析 Vorbis Comments 格式。
     * 结构: 4 bytes vendor length + vendor string + 4 bytes comment count + N comments
     * 每个 comment: 4 bytes length + "KEY=value"
     */
    private void parseVorbisComment(byte[] bytes, int offset, int length, MutableMetadata metadata) {
        int end = Math.min(offset + length, bytes.length);
        int pos = offset;
        try {
            // 跳过 vendor string
            if (pos + 4 > end) return;
            int vendorLen = int32LE(bytes, pos);
            if (vendorLen < 0 || vendorLen > end - pos - 4) return;
            pos += 4 + vendorLen;
            // 读取 comment 数量
            if (pos + 4 > end) return;
            int commentCount = int32LE(bytes, pos);
            if (commentCount < 0 || commentCount > 10000) return;
            pos += 4;
            for (int i = 0; i < commentCount && pos + 4 <= end; i++) {
                int commentLen = int32LE(bytes, pos);
                pos += 4;
                if (commentLen < 0 || pos + commentLen > end) break;
                String comment = new String(bytes, pos, commentLen, StandardCharsets.UTF_8);
                pos += commentLen;
                applyVorbisComment(metadata, comment);
            }
        } catch (RuntimeException e) {
            log.warn("Vorbis Comments 解析异常: {}", e.getMessage());
        }
    }

    private void applyVorbisComment(MutableMetadata metadata, String comment) {
        int eq = comment.indexOf('=');
        if (eq <= 0) return;
        String key = comment.substring(0, eq).toUpperCase(Locale.ROOT);
        String value = comment.substring(eq + 1);
        switch (key) {
            case "TITLE" -> metadata.title = firstNonNull(metadata.title, value);
            case "ARTIST" -> metadata.artistName = firstNonNull(metadata.artistName, value);
            case "ALBUM" -> metadata.albumTitle = firstNonNull(metadata.albumTitle, value);
            case "GENRE" -> metadata.genre = firstNonNull(metadata.genre, value);
            case "TRACKNUMBER" -> metadata.trackNumber = firstNonNull(metadata.trackNumber, value);
            case "DISCNUMBER" -> metadata.discNumber = firstNonNull(metadata.discNumber, value);
            case "LYRICS" -> metadata.lyricsRaw = firstNonNull(metadata.lyricsRaw, value);
            default -> { }
        }
    }

    // ─── M4A / AAC（MP4 ilst atoms）────────────────────────────────────────

    private Metadata parseMp4Ilst(byte[] bytes, String fileName) {
        MutableMetadata metadata = new MutableMetadata();
        // 在 moov > udta > meta > ilst 中查找
        Map<String, byte[]> atoms = findMp4IlstAtoms(bytes);
        metadata.title = parseMp4TextAtom(atoms.get("©nam"));
        metadata.artistName = parseMp4TextAtom(atoms.get("©ART"));
        metadata.albumTitle = parseMp4TextAtom(atoms.get("©alb"));
        metadata.genre = parseMp4TextAtom(atoms.get("©gen"));
        metadata.trackNumber = parseMp4TrackAtom(atoms.get("trkn"));
        metadata.discNumber = parseMp4DiscAtom(atoms.get("disk"));
        metadata.lyricsRaw = parseMp4TextAtom(atoms.get("©lyr"));
        metadata.coverDataUrl = parseMp4CoverAtom(atoms.get("covr"));
        metadata.durationSeconds = findMp4DurationSeconds(bytes);
        return metadata.toMetadata();
    }

    /**
     * 从 moov &gt; mvhd 取时长。moov 位于文件尾部（非 fast-start 编码）时读不到，留空。
     */
    private Integer findMp4DurationSeconds(byte[] bytes) {
        int pos = 0;
        while (pos + 8 <= bytes.length) {
            long size = int32BE(bytes, pos) & 0xFFFFFFFFL;
            if (size < 8 || pos + size > bytes.length) {
                break;
            }
            String type = new String(bytes, pos + 4, 4, StandardCharsets.ISO_8859_1);
            if ("moov".equals(type)) {
                return mvhdDuration(Arrays.copyOfRange(bytes, pos + 8, pos + (int) size));
            }
            pos += (int) size;
        }
        return null;
    }

    private Integer mvhdDuration(byte[] moov) {
        int pos = 0;
        while (pos + 8 <= moov.length) {
            long size = int32BE(moov, pos) & 0xFFFFFFFFL;
            if (size < 8 || pos + size > moov.length) {
                break;
            }
            String type = new String(moov, pos + 4, 4, StandardCharsets.ISO_8859_1);
            if ("mvhd".equals(type) && size >= 28) {
                int version = moov[pos + 8] & 0xFF;
                if (version == 1 && size >= 40) {
                    long timescale = int32BE(moov, pos + 28) & 0xFFFFFFFFL;
                    return toSeconds(timescale, int64BE(moov, pos + 32));
                }
                if (version == 0) {
                    long timescale = int32BE(moov, pos + 20) & 0xFFFFFFFFL;
                    return toSeconds(timescale, int32BE(moov, pos + 24) & 0xFFFFFFFFL);
                }
            }
            pos += (int) size;
        }
        return null;
    }

    private Integer toSeconds(long timescale, long duration) {
        if (timescale <= 0 || duration <= 0) {
            return null;
        }
        return (int) (duration / timescale);
    }

    /**
     * 遍历 MP4 atom 树，找到 ilst 并返回其中的子 atom。
     */
    private Map<String, byte[]> findMp4IlstAtoms(byte[] bytes) {
        Map<String, byte[]> result = new HashMap<>();
        int pos = 0;
        while (pos + 8 <= bytes.length) {
            int atomSize = int32BE(bytes, pos);
            if (atomSize < 8 || pos + atomSize > bytes.length) break;
            String atomType = new String(bytes, pos + 4, 4, StandardCharsets.ISO_8859_1);
            if ("moov".equals(atomType) || "udta".equals(atomType)) {
                // 递归进入容器 atom
                Map<String, byte[]> nested = findMp4IlstAtoms(
                        Arrays.copyOfRange(bytes, pos + 8, pos + atomSize));
                result.putAll(nested);
            } else if ("meta".equals(atomType)) {
                // meta atom 前有 4 bytes version/flags
                if (atomSize > 12) {
                    Map<String, byte[]> nested = findMp4IlstAtoms(
                            Arrays.copyOfRange(bytes, pos + 12, pos + atomSize));
                    result.putAll(nested);
                }
            } else if ("ilst".equals(atomType)) {
                // ilst 内部是一系列子 atom，每个有 8 bytes header + data
                int inner = pos + 8;
                int ilstEnd = pos + atomSize;
                while (inner + 8 <= ilstEnd) {
                    int childSize = int32BE(bytes, inner);
                    if (childSize < 8 || inner + childSize > ilstEnd) break;
                    String childType = new String(bytes, inner + 4, 4, StandardCharsets.ISO_8859_1);
                    // 跳过 atom header，找内部的 "data" atom
                    byte[] childData = Arrays.copyOfRange(bytes, inner + 8, inner + childSize);
                    byte[] dataPayload = extractMp4DataAtom(childData);
                    if (dataPayload != null) {
                        result.put(childType, dataPayload);
                    }
                    inner += childSize;
                }
            }
            pos += atomSize;
        }
        return result;
    }

    /**
     * 从 ilst 子 atom 中提取 "data" atom 的 payload。
     * 结构: [4 bytes size]["data"][4 bytes type][4 bytes locale][payload]
     */
    private byte[] extractMp4DataAtom(byte[] atomBytes) {
        int pos = 0;
        while (pos + 8 <= atomBytes.length) {
            int size = int32BE(atomBytes, pos);
            if (size < 8 || pos + size > atomBytes.length) break;
            String type = new String(atomBytes, pos + 4, 4, StandardCharsets.ISO_8859_1);
            if ("data".equals(type) && size > 16) {
                return Arrays.copyOfRange(atomBytes, pos + 16, pos + size);
            }
            pos += size;
        }
        return null;
    }

    private String parseMp4TextAtom(byte[] data) {
        if (data == null || data.length == 0) return null;
        // 文本 data atom: 前 16 bytes 已在 extractMp4DataAtom 中跳过，剩余为 UTF-8 文本
        String text = new String(data, StandardCharsets.UTF_8);
        return clean(text);
    }

    private String parseMp4TrackAtom(byte[] data) {
        if (data == null || data.length < 4) return null;
        // trkn data: [2 bytes reserved][2 bytes track number][2 bytes total]
        int track = ((data[2] & 0xFF) << 8) | (data[3] & 0xFF);
        return track > 0 ? String.valueOf(track) : null;
    }

    private String parseMp4DiscAtom(byte[] data) {
        if (data == null || data.length < 4) return null;
        // disk data: [2 bytes reserved][2 bytes disc number]
        int disc = ((data[2] & 0xFF) << 8) | (data[3] & 0xFF);
        return disc > 0 ? String.valueOf(disc) : null;
    }

    private String parseMp4CoverAtom(byte[] data) {
        if (data == null || data.length < 8) return null;
        // covr data atom: 前 4 bytes 可能是 type indicator，后跟图片数据
        // 检测 JPEG (FFD8) 或 PNG (89504E47)
        String mime;
        int imageOffset;
        if ((data[0] & 0xFF) == 0xFF && (data[1] & 0xFF) == 0xD8) {
            mime = "image/jpeg";
            imageOffset = 0;
        } else if ((data[0] & 0xFF) == 0x89 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G') {
            mime = "image/png";
            imageOffset = 0;
        } else if (data.length > 4) {
            // 可能有 4 bytes type indicator (0x0000000D for JPEG, 0x0000000E for PNG)
            if ((data[4] & 0xFF) == 0xFF && (data[5] & 0xFF) == 0xD8) {
                mime = "image/jpeg";
                imageOffset = 4;
            } else if ((data[4] & 0xFF) == 0x89 && data[5] == 'P') {
                mime = "image/png";
                imageOffset = 4;
            } else {
                mime = "image/jpeg";
                imageOffset = 0;
            }
        } else {
            return null;
        }
        byte[] image = Arrays.copyOfRange(data, imageOffset, data.length);
        return "data:" + mime + ";base64," + Base64.getEncoder().encodeToString(image);
    }

    // ─── WAV（RIFF INFO chunks）────────────────────────────────────────────

    private Metadata parseWav(byte[] bytes, String fileName, long fileSizeBytes) {
        MutableMetadata metadata = new MutableMetadata();
        // RIFF 结构: "RIFF"[4 bytes size]["WAVE" + chunks]
        // 在 chunks 中找 "LIST" -> "INFO" 子 chunk
        int pos = 12; // 跳过 RIFF header
        int byteRate = 0;
        int dataStart = 0;
        long dataSize = 0;
        while (pos + 8 <= bytes.length) {
            String chunkId = new String(bytes, pos, 4, StandardCharsets.ISO_8859_1);
            int chunkSize = int32LE(bytes, pos + 4);
            if (chunkSize < 0 || pos + 8 + chunkSize > bytes.length) break;
            if ("fmt ".equals(chunkId) && chunkSize >= 16 && pos + 24 <= bytes.length) {
                // fmt data: [2 format][2 channels][4 sampleRate][4 byteRate]...
                byteRate = int32LE(bytes, pos + 8 + 8);
            }
            if ("data".equals(chunkId)) {
                dataStart = pos + 8;
                dataSize = chunkSize;
            }
            if ("LIST".equals(chunkId) && pos + 12 <= bytes.length) {
                String listType = new String(bytes, pos + 8, 4, StandardCharsets.ISO_8859_1);
                if ("INFO".equals(listType)) {
                    parseRiffInfoChunks(bytes, pos + 12, chunkSize - 4, metadata);
                }
            }
            // 也检查内嵌的 ID3 标签
            if ("id3 ".equals(chunkId) || "ID3 ".equals(chunkId)) {
                byte[] id3Bytes = Arrays.copyOfRange(bytes, pos + 8, pos + 8 + chunkSize);
                if (id3Bytes.length >= 10 && id3Bytes[0] == 'I' && id3Bytes[1] == 'D' && id3Bytes[2] == '3') {
                    Metadata id3 = parseId3v2(id3Bytes, fileName, fileSizeBytes);
                    if (id3.hasAnyValue()) {
                        return id3;
                    }
                }
            }
            pos += 8 + chunkSize;
            // RIFF chunks 必须 2-byte 对齐
            if (chunkSize % 2 != 0) pos++;
        }
        metadata.durationSeconds = wavDuration(byteRate, dataStart, dataSize, fileSizeBytes);
        return metadata.toMetadata();
    }

    /**
     * 用 data 段字节数与 byteRate 求时长；流式写入的 WAV 会把 data 长度记成 0 或
     * 上限值，此时按文件总长扣除 data 之前的头部估算。
     */
    private Integer wavDuration(int byteRate, int dataStart, long dataSize, long fileSizeBytes) {
        if (byteRate <= 0 || dataStart <= 0) {
            return null;
        }
        long usable = dataSize;
        if (usable <= 0 || usable >= 0xFFFFF000L) {
            usable = fileSizeBytes - dataStart;
        } else if (fileSizeBytes > 0) {
            usable = Math.min(usable, fileSizeBytes - dataStart);
        }
        if (usable <= 0) {
            return null;
        }
        return (int) (usable / byteRate);
    }

    /**
     * 解析 RIFF INFO 子 chunks。
     * 每个 chunk: [4 bytes id][4 bytes size][data]
     */
    private void parseRiffInfoChunks(byte[] bytes, int offset, int length, MutableMetadata metadata) {
        int end = Math.min(offset + length, bytes.length);
        int pos = offset;
        while (pos + 8 <= end) {
            String chunkId = new String(bytes, pos, 4, StandardCharsets.ISO_8859_1);
            int chunkSize = int32LE(bytes, pos + 4);
            if (chunkSize < 0 || pos + 8 + chunkSize > end) break;
            String value = clean(new String(bytes, pos + 8, chunkSize, StandardCharsets.ISO_8859_1));
            switch (chunkId) {
                case "INAM" -> metadata.title = firstNonNull(metadata.title, value);
                case "IART" -> metadata.artistName = firstNonNull(metadata.artistName, value);
                case "IPRD" -> metadata.albumTitle = firstNonNull(metadata.albumTitle, value);
                case "IGNR" -> metadata.genre = firstNonNull(metadata.genre, value);
                case "ITRK" -> metadata.trackNumber = firstNonNull(metadata.trackNumber, value);
                case "ICMT" -> metadata.lyricsRaw = firstNonNull(metadata.lyricsRaw, value);
                default -> { }
            }
            pos += 8 + chunkSize;
            if (chunkSize % 2 != 0) pos++;
        }
    }

    // ─── FLAC PICTURE block 解析 ──────────────────────────────────────────

    /**
     * 解析 FLAC PICTURE metadata block。
     * 结构: [4 bytes type][4 bytes mime len][mime][4 bytes desc len][desc]
     *        [4 bytes width][4 bytes height][4 bytes depth][4 bytes colors]
     *        [4 bytes data len][data]
     */
    private String decodeFlacPicture(byte[] bytes, int offset, int length) {
        int pos = offset;
        int end = Math.min(offset + length, bytes.length);
        try {
            if (pos + 32 > end) return null;
            pos += 4; // skip picture type
            int mimeLen = int32BE(bytes, pos); pos += 4;
            if (mimeLen < 0 || pos + mimeLen > end) return null;
            String mime = new String(bytes, pos, mimeLen, StandardCharsets.ISO_8859_1); pos += mimeLen;
            int descLen = int32BE(bytes, pos); pos += 4 + descLen; // skip description
            pos += 16; // skip width, height, depth, colors
            if (pos + 4 > end) return null;
            int dataLen = int32BE(bytes, pos); pos += 4;
            if (dataLen < 0 || pos + dataLen > end) return null;
            byte[] image = Arrays.copyOfRange(bytes, pos, pos + dataLen);
            if (image.length == 0) return null;
            return "data:" + mime + ";base64," + Base64.getEncoder().encodeToString(image);
        } catch (RuntimeException e) {
            log.warn("FLAC PICTURE 解析异常: {}", e.getMessage());
            return null;
        }
    }

    /**
     * 解析 OGG 中的 METADATA_BLOCK_PICTURE（Vorbis spec）。
     * 结构与 FLAC PICTURE 相同，但前面有 "METADATA_BLOCK_PICTURE=" 前缀或直接 binary。
     */
    private String decodeVorbisPicture(byte[] bytes, int offset) {
        // 跳到 picture type (4 bytes)
        int pos = offset;
        if (pos + 32 > bytes.length) return null;
        return decodeFlacPicture(bytes, pos, bytes.length - pos);
    }

    // ─── ID3v2 帧解码辅助 ─────────────────────────────────────────────────

    private String decodeId3TextFrame(byte[] frame) {
        if (frame.length < 2) return null;
        Charset charset = id3Charset(frame[0]);
        return clean(new String(frame, 1, frame.length - 1, charset));
    }

    private String decodeId3UnsynchronizedLyrics(byte[] frame) {
        if (frame.length < 5) return null;
        Charset charset = id3Charset(frame[0]);
        int descriptionStart = 4;
        int lyricsStart = findId3Terminator(frame, descriptionStart, charset);
        if (lyricsStart < 0 || lyricsStart >= frame.length) return null;
        return clean(new String(frame, lyricsStart, frame.length - lyricsStart, charset));
    }

    private String decodeId3AttachedPicture(byte[] frame) {
        if (frame.length < 5) return null;
        Charset charset = id3Charset(frame[0]);
        int mimeEnd = indexOfZero(frame, 1);
        if (mimeEnd < 0 || mimeEnd + 2 >= frame.length) return null;
        String mime = new String(frame, 1, mimeEnd - 1, StandardCharsets.ISO_8859_1);
        int descriptionStart = mimeEnd + 2;
        int imageStart = findId3Terminator(frame, descriptionStart, charset);
        if (imageStart < 0 || imageStart >= frame.length) return null;
        byte[] image = Arrays.copyOfRange(frame, imageStart, frame.length);
        if (image.length == 0 || mime.isBlank()) return null;
        return "data:" + mime + ";base64," + Base64.getEncoder().encodeToString(image);
    }

    // ─── 通用工具方法 ──────────────────────────────────────────────────────

    private int int32BE(byte[] bytes, int offset) {
        return ((bytes[offset] & 0xFF) << 24)
                | ((bytes[offset + 1] & 0xFF) << 16)
                | ((bytes[offset + 2] & 0xFF) << 8)
                | (bytes[offset + 3] & 0xFF);
    }

    private long int64BE(byte[] bytes, int offset) {
        long value = 0;
        for (int index = 0; index < 8; index++) {
            value = (value << 8) | (bytes[offset + index] & 0xFFL);
        }
        return value;
    }

    /**
     * 按大端位序读取跨字节的字段（FLAC STREAMINFO 的采样率与总采样数都不是字节对齐的）。
     *
     * @param bitOffset 从数组起始算起的位偏移
     * @param bitLength 读取位数，不超过 64
     * @return 读取到的无符号值；越界时返回 0
     */
    private long readBitsBE(byte[] bytes, long bitOffset, int bitLength) {
        if (bitLength <= 0 || bitLength > 64) {
            return 0;
        }
        long lastBit = bitOffset + bitLength;
        if (lastBit > (long) bytes.length * 8) {
            return 0;
        }
        long value = 0;
        for (long bit = bitOffset; bit < lastBit; bit++) {
            int byteIndex = (int) (bit >>> 3);
            int bitInByte = (int) (7 - (bit & 7));
            value = (value << 1) | ((bytes[byteIndex] >>> bitInByte) & 1);
        }
        return value;
    }

    /**
     * 解析标签里的十进制长度字段；非数字或空值返回 null，不抛异常。
     */
    private Integer parsePositiveInt(String value) {
        if (value == null) {
            return null;
        }
        String digits = value.trim();
        if (digits.isEmpty()) {
            return null;
        }
        try {
            int parsed = Integer.parseInt(digits);
            return parsed > 0 ? parsed : null;
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private int int32LE(byte[] bytes, int offset) {
        return (bytes[offset] & 0xFF)
                | ((bytes[offset + 1] & 0xFF) << 8)
                | ((bytes[offset + 2] & 0xFF) << 16)
                | ((bytes[offset + 3] & 0xFF) << 24);
    }

    private int synchsafeInt(byte[] bytes, int offset) {
        return ((bytes[offset] & 0x7F) << 21)
                | ((bytes[offset + 1] & 0x7F) << 14)
                | ((bytes[offset + 2] & 0x7F) << 7)
                | (bytes[offset + 3] & 0x7F);
    }

    private int int32(byte[] bytes, int offset) {
        return ((bytes[offset] & 0xFF) << 24)
                | ((bytes[offset + 1] & 0xFF) << 16)
                | ((bytes[offset + 2] & 0xFF) << 8)
                | (bytes[offset + 3] & 0xFF);
    }

    private int indexOfZero(byte[] bytes, int start) {
        for (int i = start; i < bytes.length; i++) {
            if (bytes[i] == 0) return i;
        }
        return -1;
    }

    private int findId3Terminator(byte[] bytes, int start, Charset charset) {
        if (charset.equals(StandardCharsets.UTF_16) || charset.equals(StandardCharsets.UTF_16BE)) {
            for (int i = start; i + 1 < bytes.length; i += 2) {
                if (bytes[i] == 0 && bytes[i + 1] == 0) return i + 2;
            }
            return -1;
        }
        int i = indexOfZero(bytes, start);
        return i < 0 ? -1 : i + 1;
    }

    private Charset id3Charset(byte encoding) {
        return switch (encoding & 0xFF) {
            case 1 -> StandardCharsets.UTF_16;
            case 2 -> StandardCharsets.UTF_16BE;
            case 3 -> StandardCharsets.UTF_8;
            default -> StandardCharsets.ISO_8859_1;
        };
    }

    private String clean(String value) {
        if (value == null) return null;
        String cleaned = value.replace(" ", "").trim();
        return cleaned.isBlank() ? null : cleaned;
    }

    private String firstNonNull(String a, String b) {
        if (a != null && !a.isBlank()) return a;
        if (b != null && !b.isBlank()) return b;
        return null;
    }

    // ─── 数据模型 ──────────────────────────────────────────────────────────

    public record Metadata(
            String title,
            String artistName,
            String albumTitle,
            String genre,
            String lyricsRaw,
            String coverDataUrl,
            String trackNumber,
            String discNumber,
            Integer bitrate,
            Integer sampleRate,
            Integer durationSeconds
    ) {
        static Metadata empty() {
            return new Metadata(null, null, null, null, null, null, null, null, null, null, null);
        }

        /**
         * 是否含可写入标签的用户元数据。时长与码率属于容器技术信息，
         * 不参与判定，否则仅有长度的文件会被标成已匹配而不再进刮削队列。
         */
        boolean hasAnyValue() {
            return hasText(title)
                    || hasText(artistName)
                    || hasText(albumTitle)
                    || hasText(genre)
                    || hasText(lyricsRaw)
                    || hasText(coverDataUrl)
                    || hasText(trackNumber)
                    || hasText(discNumber);
        }

        private boolean hasText(String value) {
            return value != null && !value.isBlank();
        }
    }

    private static final class MutableMetadata {
        private String title;
        private String artistName;
        private String albumTitle;
        private String genre;
        private String lyricsRaw;
        private String coverDataUrl;
        private String trackNumber;
        private String discNumber;
        private Integer bitrate;
        private Integer sampleRate;
        private Integer durationSeconds;

        private Metadata toMetadata() {
            return new Metadata(title, artistName, albumTitle, genre, lyricsRaw, coverDataUrl, trackNumber,
                    discNumber, bitrate, sampleRate, durationSeconds);
        }
    }
}
