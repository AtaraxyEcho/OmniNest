package com.omninest.modules.video.service;

import java.time.Year;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

@Slf4j
@Component
public class SimpleFileNameParser {
    private static final Pattern YEAR_PATTERN = Pattern.compile("\\b(19\\d{2}|20\\d{2})\\b");

    /** 中文季: 第一季、第3季 等。「部」单列，只有带集数标记时才算季。 */
    private static final Pattern CN_SEASON_PATTERN = Pattern.compile(
            "第([一二三四五六七八九十百\\d]+)季");

    /** 中文分部和集数标记：用于判断「第X部」是否属于剧集。 */
    private static final Pattern CN_PART_PATTERN = Pattern.compile(
            "第([一二三四五六七八九十百\\d]+)部");

    /** 中文集: 第01集、第1话、第2話、第3回 等 */
    private static final Pattern CN_EPISODE_PATTERN = Pattern.compile(
            "第(\\d{1,3})[集话話回]");

    /** 中文季+集组合: 第1季03、第1季EP02 等；末尾必须不是字母或数字，避免吃掉年份前三位。 */
    private static final Pattern CN_SEASON_EPISODE_PATTERN = Pattern.compile(
            "第([一二三四五六七八九十百\\d]+)[季部][\\s.\\-_]*(?:[Ee][Pp]?)?(\\d{1,3})(?![\\dA-Za-z])");

    /** 西方格式: S01E02、s1e2、S01.E02 等 */
    private static final Pattern WESTERN_EPISODE_PATTERN = Pattern.compile(
            "(?i)[Ss](\\d{1,2})[ ._-]?[Ee](\\d{1,2})");

    /** 裸集数: 仅当已识别到季时，匹配末尾的 -01、_02、.03 等 */
    private static final Pattern BARE_EPISODE_PATTERN = Pattern.compile(
            "[\\s.\\-_](\\d{1,3})(?![\\dA-Za-z])\\s*$");

    /** 常见视频标签 */
    private static final Pattern TAG_PATTERN = Pattern.compile(
            "(?i)\\b(480p|720p|1080p|2160p|4k|8k|"
            + "web[- ]?dl|webrip|bluray|brrip|hdrip|"
            + "x264|x265|h264|h265|hevc|aac|dts|atmos|proper|repack)\\b");

    /** 中文数字 → 阿拉伯数字映射 */
    private static final Map<String, Integer> CN_DIGITS = Map.ofEntries(
            Map.entry("一", 1), Map.entry("二", 2), Map.entry("三", 3),
            Map.entry("四", 4), Map.entry("五", 5), Map.entry("六", 6),
            Map.entry("七", 7), Map.entry("八", 8), Map.entry("九", 9),
            Map.entry("十", 10), Map.entry("十一", 11), Map.entry("十二", 12));

    public FileNameGuess parse(String fileName) {
        String baseName = removeExtension(fileName == null ? "" : fileName.trim());

        Integer season = null;
        Integer episode = null;
        int titleEnd = baseName.length();

        // 1. 中文季/部 + 集数组合（最高优先级）
        Matcher cnComboMatcher = CN_SEASON_EPISODE_PATTERN.matcher(baseName);
        if (cnComboMatcher.find()) {
            season = parseChineseNumber(cnComboMatcher.group(1));
            episode = Integer.parseInt(cnComboMatcher.group(2));
            titleEnd = cnComboMatcher.start();
        }

        // 2. 中文季（独立）
        if (season == null) {
            Matcher cnSeasonMatcher = CN_SEASON_PATTERN.matcher(baseName);
            if (cnSeasonMatcher.find()) {
                season = parseChineseNumber(cnSeasonMatcher.group(1));
                titleEnd = cnSeasonMatcher.start();
            }
        }

        // 3. 中文集（独立，无季信息时）
        Matcher cnEpMatcher = CN_EPISODE_PATTERN.matcher(baseName);
        if (cnEpMatcher.find()) {
            episode = Integer.parseInt(cnEpMatcher.group(1));
            if (season == null) {
                season = 1;
            }
            titleEnd = Math.min(titleEnd, cnEpMatcher.start());
        }

        // 4. 「第X部」只有同时出现明确集数标记时才算剧集，否则是电影名的一部分。
        if (episode != null) {
            Matcher cnPartMatcher = CN_PART_PATTERN.matcher(baseName);
            if (cnPartMatcher.find()) {
                if (season == null) {
                    season = parseChineseNumber(cnPartMatcher.group(1));
                }
                titleEnd = Math.min(titleEnd, cnPartMatcher.start());
            }
        }

        // 5. 西方格式 S##E##
        Matcher westernMatcher = WESTERN_EPISODE_PATTERN.matcher(baseName);
        if (westernMatcher.find()) {
            season = Integer.parseInt(westernMatcher.group(1));
            episode = Integer.parseInt(westernMatcher.group(2));
            titleEnd = Math.min(titleEnd, westernMatcher.start());
        }

        // 6. 有季无集时，尝试末尾裸集数
        if (season != null && episode == null) {
            Matcher bareMatcher = BARE_EPISODE_PATTERN.matcher(baseName);
            if (bareMatcher.find()) {
                episode = Integer.parseInt(bareMatcher.group(1));
                titleEnd = Math.min(titleEnd, bareMatcher.start());
            }
        }

        // 年份：取最后一个非起始位置的合法年份，保护《1917.2019》《2001太空漫游.1968》这类片名。
        Matcher yearMatcher = YEAR_PATTERN.matcher(baseName);
        Integer year = null;
        int yearStart = -1;
        int maxYear = Year.now().getValue() + 1;
        while (yearMatcher.find()) {
            int candidate = Integer.parseInt(yearMatcher.group(1));
            if (candidate <= maxYear) {
                year = candidate;
                yearStart = yearMatcher.start();
            }
        }
        if (year != null && yearStart > 0) {
            titleEnd = Math.min(titleEnd, yearStart);
        }

        // 提取标题
        String title = baseName.substring(0, titleEnd)
                .replace('.', ' ')
                .replace('_', ' ')
                .replace('-', ' ');
        title = TAG_PATTERN.matcher(title).replaceAll(" ");
        title = title.replaceAll("\\s+", " ").trim();

        if (title.isEmpty()) {
            title = removeExtension(fileName == null ? "" : fileName).replaceAll("[._-]+", " ").trim();
        }
        if (title.isEmpty()) {
            title = "Untitled";
        }
        return new FileNameGuess(toDisplayTitle(title), year, season, episode);
    }

    public boolean isVideoFile(String fileName, String mimeType) {
        if (mimeType != null && mimeType.toLowerCase(Locale.ROOT).startsWith("video/")) {
            return true;
        }
        String lower = fileName == null ? "" : fileName.toLowerCase(Locale.ROOT);
        return lower.endsWith(".mp4")
                || lower.endsWith(".m4v")
                || lower.endsWith(".mkv")
                || lower.endsWith(".avi")
                || lower.endsWith(".mov")
                || lower.endsWith(".webm")
                || lower.endsWith(".ts")
                || lower.endsWith(".m2ts")
                || lower.endsWith(".flv");
    }

    private int parseChineseNumber(String text) {
        if (text == null || text.isBlank()) {
            return 1;
        }
        try {
            return Integer.parseInt(text);
        } catch (NumberFormatException ignored) {
            log.debug("忽略: {}", ignored.getMessage());
        }
        Integer mapped = CN_DIGITS.get(text);
        return mapped != null ? mapped : 1;
    }

    private String removeExtension(String fileName) {
        int index = fileName.lastIndexOf('.');
        if (index <= 0) {
            return fileName;
        }
        return fileName.substring(0, index);
    }

    private String toDisplayTitle(String value) {
        StringBuilder result = new StringBuilder();
        for (String word : value.split(" ")) {
            if (word.isBlank()) {
                continue;
            }
            if (!result.isEmpty()) {
                result.append(' ');
            }
            result.append(word.substring(0, 1).toUpperCase(Locale.ROOT));
            if (word.length() > 1) {
                result.append(word.substring(1));
            }
        }
        return result.toString();
    }
}
