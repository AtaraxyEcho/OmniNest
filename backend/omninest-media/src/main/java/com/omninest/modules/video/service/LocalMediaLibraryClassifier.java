package com.omninest.modules.video.service;

import com.omninest.modules.file.dto.LocalMediaScanEntry;
import com.omninest.modules.media.domain.MetadataStatus;
import com.omninest.modules.video.domain.MediaLibraryType;
import com.omninest.modules.video.domain.MediaMovie;
import com.omninest.modules.video.domain.MediaTvEpisode;
import com.omninest.modules.video.domain.MediaTvSeason;
import com.omninest.modules.video.domain.MediaTvSeries;
import com.omninest.modules.video.domain.MediaType;
import com.omninest.modules.video.domain.MediaVideoItem;
import com.omninest.modules.video.domain.NfoStatus;
import com.omninest.modules.video.domain.SeriesType;
import com.omninest.modules.video.domain.VideoLibrarySource;
import com.omninest.modules.video.repository.MediaMovieRepository;
import com.omninest.modules.video.repository.MediaTvEpisodeRepository;
import com.omninest.modules.video.repository.MediaTvSeasonRepository;
import com.omninest.modules.video.repository.MediaTvSeriesRepository;
import com.omninest.modules.video.repository.MediaVideoItemRepository;
import java.time.LocalDate;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 按媒体库类型把本地文件引用分类为电影或系列层级。
 *
 * <p>该服务只消费 File 模块返回的文件节点和安全相对路径，不读取宿主机路径，也不调用任何外部元数据服务。</p>
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class LocalMediaLibraryClassifier {
    private static final Pattern SEASON_DIRECTORY = Pattern.compile(
            "(?i)^(?:season|series|s)[ ._-]*(\\d{1,2})$|^第([一二三四五六七八九十百\\d]+)季$");
    private static final Pattern NAMED_WESTERN_SEASON_DIRECTORY = Pattern.compile(
            "(?i)^(.+?)[ ._-]+(?:season|series|s)[ ._-]*(\\d{1,2})$");
    private static final Pattern ROMAN_SEASON_DIRECTORY = Pattern.compile(
            "^(.+?)[ ._-]+(Ⅰ|Ⅱ|Ⅲ|Ⅳ|Ⅴ|Ⅵ|Ⅶ|Ⅷ|Ⅸ|Ⅹ|Ⅺ|Ⅻ)$");
    private static final Pattern SPECIAL_EPISODE = Pattern.compile(
            "(?i)^(?:sp|special)[ ._-]?(\\d{1,3})(?:v\\d+)?(?:$|[ ._-].*|\\[.*)");
    private static final Pattern EXPLICIT_EPISODE = Pattern.compile(
            "(?i)(?:^|[ ._-])(?:e|ep)[ ._-]?(\\d{1,4})(?:v\\d+)?(?=$|[ ._\\-\\[(])");
    private static final Pattern DASH_EPISODE = Pattern.compile(
            "(?:^|\\s)-\\s*(\\d{1,4})(?:v\\d+)?(?=$|[ ._\\-\\[(])");
    private static final Pattern STANDALONE_NUMBER = Pattern.compile("(?<!\\d)(\\d{1,4})(?!\\d)");
    private static final Pattern BRACKETED_TAG = Pattern.compile("\\[[^]]*]|【[^】]*】");
    private static final Pattern YEAR = Pattern.compile("^(?:19|20)\\d{2}$");
    private static final Set<String> GENERIC_DIRECTORIES = Set.of(
            "media", "media library", "movie", "movies", "tv", "tv series", "anime", "season", "specials"
    );

    private final SimpleFileNameParser fileNameParser;
    private final MediaVideoItemRepository videoItemRepository;
    private final MediaMovieRepository movieRepository;
    private final MediaTvSeriesRepository seriesRepository;
    private final MediaTvSeasonRepository seasonRepository;
    private final MediaTvEpisodeRepository episodeRepository;

    /**
     * 在创建 FileNode 前预览文件的媒体语义。
     *
     * @param source 媒体库来源
     * @param relativePath 安全相对路径
     * @param fileName 文件名
     * @return 候选媒体身份
     */
    public PreviewIdentity preview(VideoLibrarySource source, String relativePath, String fileName) {
        MediaLibraryType libraryType = effectiveLibraryType(source, relativePath);
        if (libraryType == MediaLibraryType.MOVIE) {
            FileNameGuess guess = movieGuess(source, relativePath, fileName);
            return new PreviewIdentity("MOVIE", guess.title(), null, null, "NEW", null);
        }
        EpisodeIdentity identity = episodeIdentity(source, relativePath, fileName);
        if (identity.episodeNumber() == null) {
            return new PreviewIdentity(
                    "EPISODE",
                    identity.seriesTitle(),
                    identity.seasonNumber(),
                    null,
                    "UNMATCHED",
                    "EPISODE_NUMBER_MISSING"
            );
        }
        return new PreviewIdentity(
                "EPISODE",
                identity.seriesTitle(),
                identity.seasonNumber(),
                identity.episodeNumber(),
                "NEW",
                null
        );
    }

    /**
     * 在独立短事务中分类一个扫描条目，避免大型媒体库把整个扫描保持为单个数据库事务。
     *
     * @param ownerUserId 所有者用户 ID
     * @param source 媒体库来源
     * @param entry File 模块返回的安全扫描条目
     * @return 分类结果
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public ClassificationOutcome classify(
            UUID ownerUserId,
            VideoLibrarySource source,
            LocalMediaScanEntry entry
    ) {
        MediaLibraryType libraryType = effectiveLibraryType(source, entry.relativePath());
        return switch (libraryType) {
            case MOVIE, ROOT -> classifyMovie(ownerUserId, source, entry);
            case TV_SERIES, ANIME -> classifyEpisode(ownerUserId, source, entry, libraryType);
        };
    }

    private ClassificationOutcome classifyMovie(
            UUID ownerUserId,
            VideoLibrarySource source,
            LocalMediaScanEntry entry
    ) {
        FileNameGuess guess = movieGuess(source, entry.relativePath(), entry.fileName());
        LocalDate releaseDate = guess.year() == null ? null : LocalDate.of(guess.year(), 1, 1);
        MediaMovie movie = findOrCreateMovie(ownerUserId, source.getId(), guess.title(), releaseDate);
        MediaVideoItem item = videoItemRepository
                .findByOwnerUserIdAndFileNodeId(ownerUserId, entry.fileNodeId())
                .orElseGet(MediaVideoItem::new);
        boolean created = item.getId() == null;
        UUID oldMovieId = item.getMovieId();
        initializeVideoItem(item, ownerUserId, source.getId(), entry.fileNodeId());
        item.setMediaType(MediaType.MOVIE.getValue());
        item.setMovieId(movie.getId());
        item.setSeriesId(null);
        item.setSeasonId(null);
        item.setEpisodeId(null);
        item.setSeasonNumber(null);
        item.setEpisodeNumber(null);
        videoItemRepository.save(item);
        deleteOrphanedMovie(ownerUserId, oldMovieId, movie.getId());
        return created ? ClassificationOutcome.CREATED : ClassificationOutcome.UPDATED;
    }

    private ClassificationOutcome classifyEpisode(
            UUID ownerUserId,
            VideoLibrarySource source,
            LocalMediaScanEntry entry,
            MediaLibraryType libraryType
    ) {
        EpisodeIdentity identity = episodeIdentity(source, entry.relativePath(), entry.fileName());
        if (identity.episodeNumber() == null) {
            log.warn("媒体库文件缺少可确认的集号，已跳过分类: sourceId={}, fileNodeId={}",
                    source.getId(), entry.fileNodeId());
            return ClassificationOutcome.UNMATCHED;
        }
        MediaTvSeries series = findOrCreateSeries(
                ownerUserId,
                source.getId(),
                identity.seriesTitle(),
                libraryType
        );
        MediaTvSeason season = findOrCreateSeason(ownerUserId, series.getId(), identity.seasonNumber());
        EpisodeResult episodeResult = findOrCreateEpisode(
                ownerUserId,
                series.getId(),
                season.getId(),
                identity.seasonNumber(),
                identity.episodeNumber()
        );
        if (episodeResult.created()) {
            season.setEpisodeCount(season.getEpisodeCount() + 1);
            seasonRepository.save(season);
        }

        MediaVideoItem item = videoItemRepository
                .findByOwnerUserIdAndFileNodeId(ownerUserId, entry.fileNodeId())
                .orElseGet(MediaVideoItem::new);
        boolean created = item.getId() == null;
        UUID oldMovieId = item.getMovieId();
        initializeVideoItem(item, ownerUserId, source.getId(), entry.fileNodeId());
        item.setMediaType(MediaType.EPISODE.getValue());
        item.setMovieId(null);
        item.setSeriesId(series.getId());
        item.setSeasonId(season.getId());
        item.setEpisodeId(episodeResult.episode().getId());
        item.setSeasonNumber(identity.seasonNumber());
        item.setEpisodeNumber(identity.episodeNumber());
        videoItemRepository.save(item);
        deleteOrphanedMovie(ownerUserId, oldMovieId, null);
        return created ? ClassificationOutcome.CREATED : ClassificationOutcome.UPDATED;
    }

    private void initializeVideoItem(MediaVideoItem item, UUID ownerUserId, UUID sourceId, UUID fileNodeId) {
        item.setOwnerUserId(ownerUserId);
        item.setLibrarySourceId(sourceId);
        item.setFileNodeId(fileNodeId);
        if (item.getMetadataStatus() == null) {
            item.setMetadataStatus(MetadataStatus.PENDING.getValue());
        }
        if (item.getNfoStatus() == null) {
            item.setNfoStatus(NfoStatus.DISABLED.getValue());
        }
    }

    private MediaMovie findOrCreateMovie(
            UUID ownerUserId,
            UUID sourceId,
            String title,
            LocalDate releaseDate
    ) {
        MediaMovie existing = releaseDate == null
                ? movieRepository
                        .findFirstByOwnerUserIdAndLibrarySourceIdAndTitleAndReleaseDateIsNullOrderByCreatedAtAsc(
                                ownerUserId, sourceId, title).orElse(null)
                : movieRepository
                        .findFirstByOwnerUserIdAndLibrarySourceIdAndTitleAndReleaseDateOrderByCreatedAtAsc(
                                ownerUserId, sourceId, title, releaseDate).orElse(null);
        if (existing != null) {
            return existing;
        }
        MediaMovie movie = new MediaMovie();
        movie.setOwnerUserId(ownerUserId);
        movie.setLibrarySourceId(sourceId);
        movie.setTitle(title);
        movie.setReleaseDate(releaseDate);
        movie.setMetadataStatus(MetadataStatus.PENDING.getValue());
        return movieRepository.save(movie);
    }

    private MediaTvSeries findOrCreateSeries(
            UUID ownerUserId,
            UUID sourceId,
            String title,
            MediaLibraryType libraryType
    ) {
        return seriesRepository
                .findFirstByOwnerUserIdAndLibrarySourceIdAndTitleIgnoreCaseOrderByCreatedAtAsc(
                        ownerUserId, sourceId, title)
                .orElseGet(() -> {
                    MediaTvSeries series = new MediaTvSeries();
                    series.setOwnerUserId(ownerUserId);
                    series.setLibrarySourceId(sourceId);
                    series.setTitle(title);
                    series.setSortTitle(title);
                    series.setSeriesType(libraryType == MediaLibraryType.ANIME
                            ? SeriesType.ANIME.getValue()
                            : SeriesType.TV.getValue());
                    series.setMetadataStatus(MetadataStatus.PENDING.getValue());
                    return seriesRepository.save(series);
                });
    }

    private MediaTvSeason findOrCreateSeason(UUID ownerUserId, UUID seriesId, int seasonNumber) {
        return seasonRepository.findByOwnerUserIdAndSeriesIdAndSeasonNumber(ownerUserId, seriesId, seasonNumber)
                .orElseGet(() -> {
                    MediaTvSeason season = new MediaTvSeason();
                    season.setOwnerUserId(ownerUserId);
                    season.setSeriesId(seriesId);
                    season.setSeasonNumber(seasonNumber);
                    season.setTitle(seasonNumber == 0 ? "特别篇" : "第 " + seasonNumber + " 季");
                    season.setEpisodeCount(0);
                    return seasonRepository.save(season);
                });
    }

    private EpisodeResult findOrCreateEpisode(
            UUID ownerUserId,
            UUID seriesId,
            UUID seasonId,
            int seasonNumber,
            int episodeNumber
    ) {
        MediaTvEpisode existing = episodeRepository
                .findByOwnerUserIdAndSeriesIdAndSeasonNumberAndEpisodeNumber(
                        ownerUserId, seriesId, seasonNumber, episodeNumber)
                .orElse(null);
        if (existing != null) {
            return new EpisodeResult(existing, false);
        }
        MediaTvEpisode episode = new MediaTvEpisode();
        episode.setOwnerUserId(ownerUserId);
        episode.setSeriesId(seriesId);
        episode.setSeasonId(seasonId);
        episode.setSeasonNumber(seasonNumber);
        episode.setEpisodeNumber(episodeNumber);
        episode.setTitle("第 " + episodeNumber + " 集");
        episode.setMetadataStatus(MetadataStatus.PENDING.getValue());
        return new EpisodeResult(episodeRepository.save(episode), true);
    }

    private void deleteOrphanedMovie(UUID ownerUserId, UUID oldMovieId, UUID retainedMovieId) {
        if (oldMovieId == null || oldMovieId.equals(retainedMovieId)) {
            return;
        }
        if (videoItemRepository.countByOwnerUserIdAndMovieId(ownerUserId, oldMovieId) == 0) {
            movieRepository.deleteById(oldMovieId);
        }
    }

    private FileNameGuess movieGuess(VideoLibrarySource source, String relativePath, String fileName) {
        List<String> directories = relativeDirectories(source, relativePath);
        if (!directories.isEmpty()) {
            String directory = directories.get(directories.size() - 1);
            if (!isGenericDirectory(directory) && seasonNumber(directory) == null) {
                FileNameGuess directoryGuess = fileNameParser.parse(directory);
                FileNameGuess fileGuess = fileNameParser.parse(fileName);
                return new FileNameGuess(
                        directoryGuess.title(),
                        directoryGuess.year() == null ? fileGuess.year() : directoryGuess.year(),
                        null,
                        null
                );
            }
        }
        FileNameGuess guess = fileNameParser.parse(fileName);
        return new FileNameGuess(guess.title(), guess.year(), null, null);
    }

    /**
     * 混合根来源按安全相对路径的第一级目录选择分类器。未知目录默认按电影处理，
     * 保留单类型来源的既有行为并避免把一整个根目录误判为剧集。
     */
    private MediaLibraryType effectiveLibraryType(VideoLibrarySource source, String relativePath) {
        MediaLibraryType configured = MediaLibraryType.valueOf(source.getLibraryType());
        if (configured != MediaLibraryType.ROOT) {
            return configured;
        }
        String path = relativePath == null ? "" : relativePath.replace('\\', '/');
        String root = source.getRelativeRoot() == null
                ? "."
                : source.getRelativeRoot().replace('\\', '/');
        if (!".".equals(root) && path.startsWith(root + "/")) {
            path = path.substring(root.length() + 1);
        }
        int separator = path.indexOf('/');
        if (separator < 0) {
            return MediaLibraryType.MOVIE;
        }
        String category = path.substring(0, separator).trim().toLowerCase(Locale.ROOT);
        return switch (category) {
            case "anime", "动画", "动漫" -> MediaLibraryType.ANIME;
            case "tv", "tv series", "tv-series", "series", "剧集" -> MediaLibraryType.TV_SERIES;
            case "movie", "movies", "电影" -> MediaLibraryType.MOVIE;
            default -> MediaLibraryType.MOVIE;
        };
    }

    private EpisodeIdentity episodeIdentity(VideoLibrarySource source, String relativePath, String fileName) {
        List<String> directories = relativeDirectories(source, relativePath);
        FileNameGuess fileGuess = fileNameParser.parse(fileName);
        String seriesTitle = directories.stream()
                .map(this::directoryIdentity)
                .filter(identity -> identity.title() != null)
                .filter(identity -> !isGenericDirectory(identity.title()))
                .findFirst()
                .map(DirectoryIdentity::title)
                .orElseGet(() -> cleanSeriesTitle(fileName, fileGuess));
        Integer directorySeason = directories.stream()
                .map(this::directoryIdentity)
                .map(DirectoryIdentity::seasonNumber)
                .filter(number -> number != null)
                .findFirst()
                .orElse(null);
        Integer specialEpisodeNumber = specialEpisodeNumber(fileName);
        int seasonNumber;
        if (specialEpisodeNumber != null) {
            seasonNumber = 0;
        } else if (fileGuess.seasonNumber() != null) {
            seasonNumber = fileGuess.seasonNumber();
        } else {
            seasonNumber = directorySeason == null ? 1 : directorySeason;
        }
        Integer episodeNumber = specialEpisodeNumber != null
                ? specialEpisodeNumber
                : fileGuess.episodeNumber() != null
                        ? fileGuess.episodeNumber()
                        : inferEpisodeNumber(fileName);
        return new EpisodeIdentity(seriesTitle, seasonNumber, episodeNumber);
    }

    private DirectoryIdentity directoryIdentity(String directory) {
        String trimmed = directory.trim();
        Integer standaloneSeason = seasonNumber(trimmed);
        if (standaloneSeason != null) {
            return new DirectoryIdentity(null, standaloneSeason);
        }

        FileNameGuess parsed = fileNameParser.parse(trimmed);
        if (parsed.seasonNumber() != null) {
            return new DirectoryIdentity(parsed.title(), parsed.seasonNumber());
        }

        Matcher western = NAMED_WESTERN_SEASON_DIRECTORY.matcher(trimmed);
        if (western.matches()) {
            return new DirectoryIdentity(
                    fileNameParser.parse(western.group(1)).title(),
                    Integer.parseInt(western.group(2))
            );
        }

        Matcher roman = ROMAN_SEASON_DIRECTORY.matcher(trimmed);
        if (roman.matches()) {
            return new DirectoryIdentity(
                    fileNameParser.parse(roman.group(1)).title(),
                    romanNumber(roman.group(2))
            );
        }
        return new DirectoryIdentity(parsed.title(), null);
    }

    private List<String> relativeDirectories(VideoLibrarySource source, String relativePath) {
        String path = relativePath.replace('\\', '/');
        String root = source.getRelativeRoot().replace('\\', '/');
        if (!".".equals(root) && path.startsWith(root + "/")) {
            path = path.substring(root.length() + 1);
        }
        String[] segments = path.split("/");
        if (segments.length <= 1) {
            return List.of();
        }
        return Arrays.asList(segments).subList(0, segments.length - 1);
    }

    private Integer seasonNumber(String directory) {
        Matcher matcher = SEASON_DIRECTORY.matcher(directory.trim());
        if (!matcher.matches()) {
            return "specials".equalsIgnoreCase(directory.trim()) ? 0 : null;
        }
        String western = matcher.group(1);
        if (western != null) {
            return Integer.parseInt(western);
        }
        return chineseNumber(matcher.group(2));
    }

    private Integer inferEpisodeNumber(String fileName) {
        String base = stripExtension(fileName);
        Matcher explicit = EXPLICIT_EPISODE.matcher(base);
        if (explicit.find()) {
            return Integer.parseInt(explicit.group(1));
        }
        Matcher dash = DASH_EPISODE.matcher(base);
        if (dash.find()) {
            return Integer.parseInt(dash.group(1));
        }
        String cleaned = BRACKETED_TAG.matcher(base).replaceAll(" ");
        Matcher number = STANDALONE_NUMBER.matcher(cleaned);
        Integer candidate = null;
        while (number.find()) {
            String value = number.group(1);
            if (YEAR.matcher(value).matches() || isResolution(value)) {
                continue;
            }
            candidate = Integer.valueOf(value);
        }
        return candidate;
    }

    private Integer specialEpisodeNumber(String fileName) {
        Matcher matcher = SPECIAL_EPISODE.matcher(stripExtension(fileName));
        return matcher.matches() ? Integer.valueOf(matcher.group(1)) : null;
    }

    private String cleanSeriesTitle(String fileName, FileNameGuess fileGuess) {
        Integer episode = inferEpisodeNumber(fileName);
        if (episode == null) {
            return fileGuess.title();
        }
        String base = BRACKETED_TAG.matcher(stripExtension(fileName)).replaceAll(" ");
        base = base.replaceFirst("(?i)(?:[ ._-]+(?:e|ep)?[ ._-]*" + episode + ")(?:v\\d+)?(?:[ ._-]*)$", " ");
        String title = base.replace('.', ' ').replace('_', ' ').replace('-', ' ')
                .replaceAll("\\s+", " ").trim();
        return title.isBlank() ? fileGuess.title() : title;
    }

    private boolean isGenericDirectory(String directory) {
        return GENERIC_DIRECTORIES.contains(directory.trim().toLowerCase(Locale.ROOT));
    }

    private boolean isResolution(String value) {
        return "480".equals(value) || "720".equals(value) || "1080".equals(value) || "2160".equals(value);
    }

    private int chineseNumber(String value) {
        if (value == null || value.isBlank()) {
            return 1;
        }
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException ignored) {
            return switch (value) {
                case "一" -> 1;
                case "二" -> 2;
                case "三" -> 3;
                case "四" -> 4;
                case "五" -> 5;
                case "六" -> 6;
                case "七" -> 7;
                case "八" -> 8;
                case "九" -> 9;
                case "十" -> 10;
                case "十一" -> 11;
                case "十二" -> 12;
                default -> 1;
            };
        }
    }

    private int romanNumber(String value) {
        return switch (value) {
            case "Ⅰ" -> 1;
            case "Ⅱ" -> 2;
            case "Ⅲ" -> 3;
            case "Ⅳ" -> 4;
            case "Ⅴ" -> 5;
            case "Ⅵ" -> 6;
            case "Ⅶ" -> 7;
            case "Ⅷ" -> 8;
            case "Ⅸ" -> 9;
            case "Ⅹ" -> 10;
            case "Ⅺ" -> 11;
            case "Ⅻ" -> 12;
            default -> 1;
        };
    }

    private String stripExtension(String value) {
        int dot = value.lastIndexOf('.');
        return dot > 0 ? value.substring(0, dot) : value;
    }

    /** 单个文件分类结果。 */
    public enum ClassificationOutcome {
        CREATED,
        UPDATED,
        UNMATCHED
    }

    /** 候选审核阶段可显示的媒体语义。 */
    public record PreviewIdentity(
            String candidateType,
            String groupTitle,
            Integer seasonNumber,
            Integer episodeNumber,
            String matchStatus,
            String reasonCode
    ) {
    }

    private record EpisodeIdentity(String seriesTitle, int seasonNumber, Integer episodeNumber) {
    }

    private record DirectoryIdentity(String title, Integer seasonNumber) {
    }

    private record EpisodeResult(MediaTvEpisode episode, boolean created) {
    }
}
