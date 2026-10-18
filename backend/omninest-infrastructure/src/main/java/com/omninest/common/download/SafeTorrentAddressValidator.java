package com.omninest.common.download;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 校验种子文件内嵌的对外地址。
 * 下载器拿到种子后会自行连接 announce、announce-list 与 url-list 中的地址，
 * 提交前的静态闸门必须读到种子内部，否则种子本身就成了绕过初始校验的通道。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class SafeTorrentAddressValidator implements TorrentAddressValidator {
    private static final Set<String> TRACKER_KEYS = Set.of("announce");
    private static final Set<String> TRACKER_GROUP_KEYS = Set.of("announce-list");
    private static final Set<String> WEB_SEED_KEYS = Set.of("url-list", "http-seed-list");
    private static final int MAX_DEPTH = 16;
    private static final int PIECE_HASH_BYTES = 20;
    private static final String MALFORMED_MESSAGE = "种子文件格式不正确";

    private final SafeUrlValidator safeUrlValidator;

    /**
     * 解析种子的顶层字典并校验其中的对外地址。
     *
     * @param torrentBytes 种子文件字节
     */
    @Override
    public void validate(byte[] torrentBytes) {
        List<String> trackers = new ArrayList<>();
        List<String> webSeeds = new ArrayList<>();
        if (torrentBytes == null || torrentBytes.length == 0) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, MALFORMED_MESSAGE);
        }
        new Cursor(torrentBytes).readTopLevel(trackers, webSeeds);
        webSeeds.forEach(url -> EmbeddedTargetGuard.requireWebSeed(safeUrlValidator, url));
        trackers.forEach(tracker -> EmbeddedTargetGuard.requireTracker(safeUrlValidator, tracker));
    }

    /**
     * 结构判定：顶层字典里有 info，且 info 带合法分片表，才认作种子。
     * 与 validate 分开的理由是调用方要"先认种子、再校验地址"，不能拿校验异常当识别手段：
     * 普通下载物（含以 d 开头的文本）必须原样入库，只有真种子才需要过内嵌地址闸门。
     *
     * @param candidate 待判定的字节
     * @return 结构上是种子时为真
     */
    @Override
    public boolean looksLikeTorrent(byte[] candidate) {
        if (candidate == null || candidate.length == 0) {
            return false;
        }
        try {
            return new Cursor(candidate).hasBittorrentInfo();
        } catch (BusinessException exception) {
            return false;
        }
    }

    /**
     * 定位读取的 bencode 游标：只解出关心的字段，其余值原样跳过；结构不合法即拒绝。
     */
    private static final class Cursor {
        private final byte[] data;
        private int position;

        private Cursor(byte[] data) {
            this.data = data;
        }

        private void readTopLevel(List<String> trackers, List<String> webSeeds) {
            if (peek() != 'd') {
                throw malformed();
            }
            position++;
            while (peek() != 'e') {
                String key = readString();
                if (TRACKER_KEYS.contains(key)) {
                    trackers.add(readString());
                } else if (TRACKER_GROUP_KEYS.contains(key) || WEB_SEED_KEYS.contains(key)) {
                    List<String> sink = TRACKER_GROUP_KEYS.contains(key) ? trackers : webSeeds;
                    collectStrings(1, sink);
                } else {
                    skipValue(1);
                }
            }
            position++;
        }

        /**
         * 结构识别：顶层字典里有 info，且 info 里同时有 piece length 与长度对齐的 pieces。
         */
        private boolean hasBittorrentInfo() {
            if (peek() != 'd') {
                return false;
            }
            position++;
            while (peek() != 'e') {
                if (!"info".equals(readString())) {
                    skipValue(1);
                    continue;
                }
                return hasPieceFields();
            }
            return false;
        }

        private boolean hasPieceFields() {
            if (peek() != 'd') {
                return false;
            }
            position++;
            boolean hasPieceLength = false;
            boolean hasPieces = false;
            while (peek() != 'e') {
                String key = readString();
                if ("piece length".equals(key)) {
                    skipValue(2);
                    hasPieceLength = true;
                } else if ("pieces".equals(key)) {
                    int piecesLength = readBytes().length;
                    hasPieces = piecesLength > 0 && piecesLength % PIECE_HASH_BYTES == 0;
                } else {
                    skipValue(2);
                }
            }
            return hasPieceLength && hasPieces;
        }

        private void collectStrings(int depth, List<String> sink) {
            if (depth > MAX_DEPTH) {
                throw malformed();
            }
            byte current = peek();
            if (current >= '0' && current <= '9') {
                sink.add(readString());
                return;
            }
            if (current != 'l') {
                throw malformed();
            }
            position++;
            while (peek() != 'e') {
                collectStrings(depth + 1, sink);
            }
            position++;
        }

        private void skipValue(int depth) {
            if (depth > MAX_DEPTH) {
                throw malformed();
            }
            byte current = peek();
            if (current == 'd' || current == 'l') {
                position++;
                while (peek() != 'e') {
                    if (current == 'd') {
                        readString();
                    }
                    skipValue(depth + 1);
                }
                position++;
                return;
            }
            if (current == 'i') {
                position++;
                while (peek() != 'e') {
                    position++;
                }
                position++;
                return;
            }
            if (current >= '0' && current <= '9') {
                readString();
                return;
            }
            throw malformed();
        }

        private String readString() {
            return new String(readBytes(), StandardCharsets.UTF_8);
        }

        private byte[] readBytes() {
            byte current = peek();
            if (current < '0' || current > '9') {
                throw malformed();
            }
            long length = 0;
            while (true) {
                byte digit = next();
                if (digit == ':') {
                    break;
                }
                if (digit < '0' || digit > '9') {
                    throw malformed();
                }
                length = length * 10 + (digit - '0');
                if (length > data.length) {
                    throw malformed();
                }
            }
            int size = (int) length;
            if (position + size > data.length) {
                throw malformed();
            }
            byte[] value = new byte[size];
            System.arraycopy(data, position, value, 0, size);
            position += size;
            return value;
        }

        private byte peek() {
            if (position >= data.length) {
                throw malformed();
            }
            return data[position];
        }

        private byte next() {
            byte value = peek();
            position++;
            return value;
        }

        private static BusinessException malformed() {
            return new BusinessException(ErrorCode.BAD_REQUEST, MALFORMED_MESSAGE);
        }
    }
}
