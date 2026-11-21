package com.omninest.modules.music.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.music.domain.MusicTrack;
import java.net.URI;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/** 音乐人工元数据覆盖、原值快照与恢复规则。 */
public final class MusicMetadataService {
    private static final String MANUAL_COVER_URL_KEY = "manualCoverUrl";

    private MusicMetadataService() {
    }

    public static boolean hasManualOverride(MusicTrack track) {
        return track.getManualOriginalMetadata() != null && !track.getManualOriginalMetadata().isEmpty();
    }

    public static UUID originalCoverFileId(MusicTrack track) {
        return uuidValue(copyMap(track.getManualOriginalMetadata()).get("coverFileId"));
    }

    public static String manualCoverUrl(MusicTrack track) {
        return stringValue(copyMap(track.getProviderMetadata()).get(MANUAL_COVER_URL_KEY));
    }

    public static void captureOriginal(MusicTrack track) {
        if (hasManualOverride(track)) {
            return;
        }
        Map<String, Object> original = new LinkedHashMap<>();
        original.put("title", track.getTitle());
        original.put("artistName", track.getArtistName());
        original.put("albumTitle", track.getAlbumTitle());
        original.put("genre", track.getGenre());
        original.put("coverFileId", track.getCoverFileId() == null ? null : track.getCoverFileId().toString());
        original.put("metadataStatus", track.getMetadataStatus());
        original.put("providerMetadata", copyMap(track.getProviderMetadata()));
        track.setManualOriginalMetadata(original);
        track.setManualOriginalLyricsRaw(track.getLyricsRaw());
        track.setManualOriginalLyricsTranslation(track.getLyricsTranslation());
        track.setManualOriginalLyricsWords(track.getLyricsWords());
    }

    public static boolean restoreOriginal(MusicTrack track) {
        Map<String, Object> original = copyMap(track.getManualOriginalMetadata());
        if (original.isEmpty()) {
            return false;
        }
        track.setTitle(stringValue(original.get("title")));
        track.setArtistName(stringValue(original.get("artistName")));
        track.setAlbumTitle(stringValue(original.get("albumTitle")));
        track.setGenre(stringValue(original.get("genre")));
        track.setCoverFileId(uuidValue(original.get("coverFileId")));
        track.setMetadataStatus(stringValue(original.get("metadataStatus")));
        track.setLyricsRaw(track.getManualOriginalLyricsRaw());
        track.setLyricsTranslation(track.getManualOriginalLyricsTranslation());
        track.setLyricsWords(track.getManualOriginalLyricsWords());

        track.setProviderMetadata(copyMap(original.get("providerMetadata")));
        clearOriginal(track);
        return true;
    }

    public static void clearOriginal(MusicTrack track) {
        track.setManualOriginalMetadata(null);
        track.setManualOriginalLyricsRaw(null);
        track.setManualOriginalLyricsTranslation(null);
        track.setManualOriginalLyricsWords(null);
    }

    public static void setManualCoverUrl(MusicTrack track, String value) {
        String normalized = validateCoverUrl(value);
        Map<String, Object> providerMetadata = copyMap(track.getProviderMetadata());
        if (normalized.isEmpty()) {
            providerMetadata.remove(MANUAL_COVER_URL_KEY);
        } else {
            providerMetadata.put(MANUAL_COVER_URL_KEY, normalized);
        }
        track.setProviderMetadata(providerMetadata);
    }

    public static void clearCover(MusicTrack track) {
        Map<String, Object> providerMetadata = copyMap(track.getProviderMetadata());
        providerMetadata.remove(MANUAL_COVER_URL_KEY);
        providerMetadata.remove("coverDataUrl");
        providerMetadata.remove("coverUrl");
        track.setProviderMetadata(providerMetadata);
        track.setCoverFileId(null);
    }

    public static void selectManagedCover(MusicTrack track, UUID coverFileId) {
        Map<String, Object> providerMetadata = copyMap(track.getProviderMetadata());
        providerMetadata.remove(MANUAL_COVER_URL_KEY);
        providerMetadata.remove("coverDataUrl");
        track.setProviderMetadata(providerMetadata);
        track.setCoverFileId(coverFileId);
    }

    public static void resetCoverOverride(MusicTrack track) {
        Map<String, Object> providerMetadata = copyMap(track.getProviderMetadata());
        providerMetadata.remove(MANUAL_COVER_URL_KEY);
        track.setProviderMetadata(providerMetadata);
    }

    private static String validateCoverUrl(String value) {
        String normalized = value == null ? "" : value.trim();
        if (normalized.isEmpty()) {
            return "";
        }
        try {
            URI uri = URI.create(normalized);
            String scheme = uri.getScheme();
            if (uri.getHost() == null || uri.getUserInfo() != null
                    || !("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme))) {
                throw new IllegalArgumentException("unsupported cover url");
            }
            return normalized;
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "封面地址必须是有效的 HTTP 或 HTTPS URL");
        }
    }

    private static Map<String, Object> copyMap(Object value) {
        Map<String, Object> copy = new LinkedHashMap<>();
        if (value instanceof Map<?, ?> values) {
            values.forEach((key, nested) -> {
                if (key instanceof String name) {
                    copy.put(name, nested);
                }
            });
        }
        return copy;
    }

    private static String stringValue(Object value) {
        return value == null ? null : value.toString();
    }

    private static UUID uuidValue(Object value) {
        String text = stringValue(value);
        return text == null || text.isBlank() ? null : UUID.fromString(text);
    }
}
