package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.reader.domain.ReaderItem;
import com.omninest.modules.reader.dto.ReaderDtos.UpdateItemMetadataRequest;
import java.math.BigDecimal;
import java.net.URI;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;

/** 阅读元数据字段映射与手动覆盖快照。 */
public class ReaderMetadataService {
    private static final String GENRES_ITEMS_KEY = "items";
    private static final String SERIAL_STATUS_KEY = "serialStatus";
    private static final String ISBN_KEY = "isbn";
    private static final String READER_TYPE_KEY = "readerType";
    private static final String SERIES_NAME_KEY = "seriesName";
    private static final String VOLUME_NUMBER_KEY = "volumeNumber";
    private static final String COVER_IMAGE_URL_KEY = "coverImageUrl";
    private static final String ORIGINAL_METADATA_KEY = "manualMetadataOriginal";
    private static final Set<String> READER_TYPES = Set.of("BOOK", "COMIC", "MANGA");

    private ReaderMetadataService() {
    }

    public static void apply(ReaderItem item, UpdateItemMetadataRequest request) {
        captureOriginal(item);
        if (request.title() != null && !request.title().isBlank()) {
            item.setTitle(request.title().trim());
        }
        if (request.authorName() != null) {
            item.setAuthorName(trimToNull(request.authorName()));
        }
        if (request.description() != null) {
            item.setDescription(trimToNull(request.description()));
        }
        if (request.publisher() != null) {
            item.setPublisher(trimToNull(request.publisher()));
        }
        if (request.language() != null) {
            item.setLanguage(trimToNull(request.language()));
        }
        if (request.releaseDate() != null) {
            item.setReleaseDate(request.releaseDate());
        } else if (Boolean.TRUE.equals(request.clearReleaseDate())) {
            item.setReleaseDate(null);
        }
        if (request.rating() != null) {
            item.setRating(request.rating());
        } else if (Boolean.TRUE.equals(request.clearRating())) {
            item.setRating(null);
        }
        if (request.genres() != null) {
            Map<String, Object> genres = copyMap(item.getGenres());
            genres.put(GENRES_ITEMS_KEY, request.genres().stream()
                    .filter(Objects::nonNull)
                    .map(String::trim)
                    .filter(value -> !value.isEmpty())
                    .distinct()
                    .toList());
            item.setGenres(genres);
        }

        Map<String, Object> externalIds = copyMap(item.getExternalIds());
        if (request.serialStatus() != null) {
            putTrimmed(externalIds, SERIAL_STATUS_KEY, request.serialStatus());
        }
        if (request.isbn() != null) {
            putTrimmed(externalIds, ISBN_KEY, request.isbn());
        }
        if (request.readerType() != null) {
            putTrimmed(externalIds, READER_TYPE_KEY, request.readerType().toUpperCase(Locale.ROOT));
        }
        if (request.seriesName() != null) {
            putTrimmed(externalIds, SERIES_NAME_KEY, request.seriesName());
        }
        if (request.volumeNumber() != null) {
            externalIds.put(VOLUME_NUMBER_KEY, request.volumeNumber());
        } else if (Boolean.TRUE.equals(request.clearVolumeNumber())) {
            externalIds.remove(VOLUME_NUMBER_KEY);
        }
        if (Boolean.TRUE.equals(request.clearCover())) {
            item.setCoverFileId(null);
            externalIds.remove(COVER_IMAGE_URL_KEY);
        } else if (request.coverImageUrl() != null) {
            String normalizedCoverUrl = validateCoverImageUrl(request.coverImageUrl());
            if (normalizedCoverUrl.isEmpty()) {
                externalIds.remove(COVER_IMAGE_URL_KEY);
            } else {
                externalIds.put(COVER_IMAGE_URL_KEY, normalizedCoverUrl);
            }
        }
        item.setExternalIds(externalIds);
    }

    public static boolean restoreOriginal(ReaderItem item) {
        Map<String, Object> externalIds = copyMap(item.getExternalIds());
        Map<String, Object> original = copyMap(externalIds.get(ORIGINAL_METADATA_KEY));
        if (original.isEmpty()) {
            return false;
        }
        item.setTitle(stringValue(original.get("title")));
        item.setAuthorName(stringValue(original.get("authorName")));
        item.setDescription(stringValue(original.get("description")));
        item.setPublisher(stringValue(original.get("publisher")));
        item.setLanguage(stringValue(original.get("language")));
        item.setReleaseDate(dateValue(original.get("releaseDate")));
        item.setRating(decimalValue(original.get("rating")));
        item.setGenres(copyMap(original.get("genres")));
        if (original.containsKey("coverFileId")) {
            String originalCoverFileId = stringValue(original.get("coverFileId"));
            item.setCoverFileId(originalCoverFileId == null || originalCoverFileId.isBlank()
                    ? null
                    : UUID.fromString(originalCoverFileId));
        }
        item.setExternalIds(copyMap(original.get("externalIds")));
        return true;
    }

    public static String readerType(ReaderItem item) {
        String value = stringValue(copyMap(item.getExternalIds()).get(READER_TYPE_KEY));
        value = value == null ? null : value.toUpperCase(Locale.ROOT);
        // ImmutableCollections.SetN 不接受 null，缺少 readerType 的旧条目应走
        // contentKind 的兼容回退，而不是在仪表盘组装 DTO 时中断整页响应。
        if (value != null && READER_TYPES.contains(value)) {
            return value;
        }
        return "COMIC".equalsIgnoreCase(item.getContentKind()) ? "COMIC" : "BOOK";
    }

    public static String seriesName(ReaderItem item) {
        return stringValue(copyMap(item.getExternalIds()).get(SERIES_NAME_KEY));
    }

    public static Integer volumeNumber(ReaderItem item) {
        Object value = copyMap(item.getExternalIds()).get(VOLUME_NUMBER_KEY);
        return value instanceof Number number ? number.intValue() : null;
    }

    public static String coverImageUrl(ReaderItem item) {
        Map<String, Object> externalIds = copyMap(item.getExternalIds());
        return externalIds.containsKey(COVER_IMAGE_URL_KEY)
                ? stringValue(externalIds.get(COVER_IMAGE_URL_KEY))
                : null;
    }

    public static String visibleCoverUrl(ReaderItem item) {
        Map<String, Object> externalIds = copyMap(item.getExternalIds());
        String customCoverUrl = stringValue(externalIds.get(COVER_IMAGE_URL_KEY));
        if (customCoverUrl != null && !customCoverUrl.isBlank()) {
            return customCoverUrl;
        }
        return item.getCoverFileId() == null
                ? null
                : "/api/v1/reader/items/" + item.getId() + "/cover";
    }

    public static void clearCoverImageUrl(ReaderItem item) {
        Map<String, Object> externalIds = copyMap(item.getExternalIds());
        externalIds.remove(COVER_IMAGE_URL_KEY);
        item.setExternalIds(externalIds);
    }

    public static boolean hasManualOverride(ReaderItem item) {
        return copyMap(item.getExternalIds()).containsKey(ORIGINAL_METADATA_KEY);
    }

    private static void captureOriginal(ReaderItem item) {
        Map<String, Object> externalIds = copyMap(item.getExternalIds());
        if (externalIds.containsKey(ORIGINAL_METADATA_KEY)) {
            return;
        }
        Map<String, Object> original = new LinkedHashMap<>();
        original.put("title", item.getTitle());
        original.put("authorName", item.getAuthorName());
        original.put("description", item.getDescription());
        original.put("publisher", item.getPublisher());
        original.put("language", item.getLanguage());
        original.put("releaseDate", item.getReleaseDate() == null ? null : item.getReleaseDate().toString());
        original.put("rating", item.getRating());
        original.put("genres", copyMap(item.getGenres()));
        original.put("coverFileId", item.getCoverFileId() == null ? null : item.getCoverFileId().toString());
        original.put("externalIds", externalIds);
        externalIds.put(ORIGINAL_METADATA_KEY, original);
        item.setExternalIds(externalIds);
    }

    private static String validateCoverImageUrl(String value) {
        String normalized = value.trim();
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

    private static void putTrimmed(Map<String, Object> target, String key, String value) {
        String normalized = trimToNull(value);
        if (normalized == null) {
            target.remove(key);
        } else {
            target.put(key, normalized);
        }
    }

    private static String trimToNull(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.trim();
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

    private static LocalDate dateValue(Object value) {
        if (value instanceof LocalDate date) {
            return date;
        }
        String text = stringValue(value);
        return text == null || text.isBlank() ? null : LocalDate.parse(text);
    }

    private static BigDecimal decimalValue(Object value) {
        return switch (value) {
            case BigDecimal decimal -> decimal;
            case Number number -> BigDecimal.valueOf(number.doubleValue());
            case null -> null;
            default -> new BigDecimal(value.toString());
        };
    }
}
