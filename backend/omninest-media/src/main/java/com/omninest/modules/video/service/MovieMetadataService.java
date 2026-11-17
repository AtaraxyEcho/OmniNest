package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.dto.MovieDtos.MovieMetadataUpdateRequest;
import java.net.URI;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

/** 影片人工元数据字段映射与原始信息快照。 */
public final class MovieMetadataService {
    private static final String ORIGINAL_METADATA_KEY = "manualMetadataOriginal";
    private static final String MANUAL_POSTER_URL_KEY = "manualPosterUrl";

    private MovieMetadataService() {
    }

    public static boolean hasOriginal(MediaMovie movie) {
        return copyMap(movie.getMetadata()).containsKey(ORIGINAL_METADATA_KEY);
    }

    public static String posterSourceUrl(MediaMovie movie) {
        return stringValue(copyMap(movie.getMetadata()).get(MANUAL_POSTER_URL_KEY));
    }

    public static void captureOriginal(MediaMovie movie, String posterExternalUrl, UUID posterFileNodeId) {
        Map<String, Object> metadata = copyMap(movie.getMetadata());
        if (metadata.containsKey(ORIGINAL_METADATA_KEY)) {
            return;
        }
        Map<String, Object> original = new LinkedHashMap<>();
        original.put("title", movie.getTitle());
        original.put("originalTitle", movie.getOriginalTitle());
        original.put("releaseDate", movie.getReleaseDate() == null ? null : movie.getReleaseDate().toString());
        original.put("overview", movie.getOverview());
        original.put("runtimeSeconds", movie.getRuntimeSeconds());
        original.put("rating", movie.getRating());
        original.put("genres", copyList(movie.getGenres()));
        original.put("castMembers", copyList(movie.getCastMembers()));
        UUID originalPosterFileId = posterFileNodeId == null ? movie.getPosterFileId() : posterFileNodeId;
        original.put("posterFileId", originalPosterFileId == null ? null : originalPosterFileId.toString());
        original.put("posterExternalUrl", posterExternalUrl);
        original.put("metadataStatus", movie.getMetadataStatus());
        original.put("metadata", metadata);
        metadata.put(ORIGINAL_METADATA_KEY, original);
        movie.setMetadata(metadata);
    }

    public static void applySupplemental(MediaMovie movie, MovieMetadataUpdateRequest request) {
        if (request.genres() != null) {
            movie.setGenres(genreMaps(request.genres(), movie.getGenres()));
        }
        if (request.rating() != null) {
            if (!Double.isFinite(request.rating()) || request.rating() < 0 || request.rating() > 10) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "评分须为 0 到 10 之间的数字");
            }
            movie.setRating(request.rating());
        }
        if (request.cast() != null) {
            movie.setCastMembers(castMaps(request.cast(), movie.getCastMembers()));
        }

        Map<String, Object> metadata = copyMap(movie.getMetadata());
        metadata.put("manualEdited", true);
        metadata.put("manualEditedAt", Instant.now().toString());
        if (request.posterUrl() != null) {
            String posterUrl = validatePosterUrl(request.posterUrl());
            if (posterUrl == null) {
                metadata.remove(MANUAL_POSTER_URL_KEY);
            } else {
                metadata.put(MANUAL_POSTER_URL_KEY, posterUrl);
            }
        }
        movie.setMetadata(metadata);
    }

    public static RestoredPoster restoreOriginal(MediaMovie movie) {
        Map<String, Object> metadata = copyMap(movie.getMetadata());
        Map<String, Object> original = copyMap(metadata.get(ORIGINAL_METADATA_KEY));
        if (original.isEmpty()) {
            return new RestoredPoster(null, null, false);
        }
        movie.setTitle(stringValue(original.get("title")));
        movie.setOriginalTitle(stringValue(original.get("originalTitle")));
        movie.setReleaseDate(dateValue(original.get("releaseDate")));
        movie.setOverview(stringValue(original.get("overview")));
        movie.setRuntimeSeconds(integerValue(original.get("runtimeSeconds")));
        movie.setRating(doubleValue(original.get("rating")));
        movie.setGenres(copyList(original.get("genres")));
        movie.setCastMembers(copyList(original.get("castMembers")));
        movie.setMetadataStatus(stringValue(original.get("metadataStatus")));
        Map<String, Object> restoredMetadata = copyMap(original.get("metadata"));
        String posterExternalUrl = stringValue(original.get("posterExternalUrl"));
        if (posterExternalUrl != null && !posterExternalUrl.isBlank()) {
            restoredMetadata.put(MANUAL_POSTER_URL_KEY, posterExternalUrl);
        }
        movie.setMetadata(restoredMetadata);
        return new RestoredPoster(
                uuidValue(original.get("posterFileId")),
                posterExternalUrl,
                true
        );
    }

    public static String validatePosterUrl(String value) {
        String normalized = value == null ? "" : value.trim();
        if (normalized.isEmpty()) {
            return null;
        }
        try {
            URI uri = URI.create(normalized);
            String scheme = uri.getScheme();
            if (uri.getHost() == null || uri.getUserInfo() != null
                    || !("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme))) {
                throw new IllegalArgumentException("unsupported poster url");
            }
            return normalized;
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "海报地址必须是有效的 HTTP 或 HTTPS URL");
        }
    }

    private static List<Map<String, Object>> genreMaps(List<String> values, List<Map<String, Object>> existing) {
        Map<String, Map<String, Object>> byName = new LinkedHashMap<>();
        for (Map<String, Object> value : safeList(existing)) {
            String name = stringValue(value.get("name"));
            if (name != null) {
                byName.put(name.toLowerCase(Locale.ROOT), value);
            }
        }
        return values.stream()
                .filter(Objects::nonNull)
                .map(String::trim)
                .filter(value -> !value.isEmpty())
                .distinct()
                .map(name -> {
                    Map<String, Object> genre = new LinkedHashMap<>(
                            byName.getOrDefault(name.toLowerCase(Locale.ROOT), Map.of()));
                    genre.put("name", name);
                    return genre;
                })
                .toList();
    }

    private static List<Map<String, Object>> castMaps(List<String> values, List<Map<String, Object>> existing) {
        Map<String, Map<String, Object>> byName = new LinkedHashMap<>();
        for (Map<String, Object> value : safeList(existing)) {
            String name = stringValue(value.get("name"));
            if (name != null) {
                byName.put(name.toLowerCase(Locale.ROOT), value);
            }
        }
        List<Map<String, Object>> cast = new ArrayList<>();
        for (String raw : values) {
            if (raw == null || raw.isBlank()) {
                continue;
            }
            String name = raw.trim();
            Map<String, Object> member = new LinkedHashMap<>(
                    byName.getOrDefault(name.toLowerCase(Locale.ROOT), Map.of()));
            member.put("name", name);
            member.put("order", cast.size());
            cast.add(member);
        }
        return cast;
    }

    private static List<Map<String, Object>> copyList(Object value) {
        List<Map<String, Object>> copied = new ArrayList<>();
        if (value instanceof List<?> list) {
            for (Object item : list) {
                if (item instanceof Map<?, ?> map) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    map.forEach((key, nested) -> {
                        if (key instanceof String name) {
                            row.put(name, nested);
                        }
                    });
                    copied.add(row);
                }
            }
        }
        return copied;
    }

    private static List<Map<String, Object>> safeList(List<Map<String, Object>> value) {
        return value == null ? List.of() : value;
    }

    private static Map<String, Object> copyMap(Object value) {
        Map<String, Object> copied = new LinkedHashMap<>();
        if (value instanceof Map<?, ?> map) {
            map.forEach((key, nested) -> {
                if (key instanceof String name) {
                    copied.put(name, nested);
                }
            });
        }
        return copied;
    }

    private static String stringValue(Object value) {
        return value == null ? null : value.toString();
    }

    private static LocalDate dateValue(Object value) {
        String text = stringValue(value);
        return text == null || text.isBlank() ? null : LocalDate.parse(text);
    }

    private static Integer integerValue(Object value) {
        return value instanceof Number number ? number.intValue() : null;
    }

    private static Double doubleValue(Object value) {
        return value instanceof Number number ? number.doubleValue() : null;
    }

    private static UUID uuidValue(Object value) {
        String text = stringValue(value);
        return text == null || text.isBlank() ? null : UUID.fromString(text);
    }

    public record RestoredPoster(UUID fileNodeId, String externalUrl, boolean restored) {
    }
}
