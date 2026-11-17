package com.omninest.modules.reader.service;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 漫画分卷命名解析器：从文件名中识别卷、话、集、章、回、篇、目、册等常见分卷格式，
 * 同时兼容简体/繁体/日式异体字与中文数字。
 *
 * @author OmniNest
 */
public final class ComicVolumeParser {

    private ComicVolumeParser() {
    }

    /**
     * 分卷解析结果。
     *
     * @param partKind 分卷类型（VOL/EPISODE/CHAPTER/SEASON/SEASON_EP/OTHER）
     * @param partNo 分卷序号（区间取起始值）
     * @param rangeEnd 区间结束值，无区间时为 null
     * @param matched 是否识别到分卷信号
     */
    public record PartInfo(
            String partKind,
            Integer partNo,
            Integer rangeEnd,
            boolean matched
    ) {
    }

    /** 简体/繁体/日式异体字 → 分卷类型映射。 */
    private static final String VOL_KINDS = "卷巻册冊部本編编";
    private static final String EPISODE_KINDS = "话話集号號話";
    private static final String CHAPTER_KINDS = "章回篇目";

    // 前缀式：卷01 / 話001-010 / 话001 / 第X话 / 第1卷 / 第三卷
    private static final Pattern PREFIXED = Pattern.compile(
            "([" + VOL_KINDS + EPISODE_KINDS + CHAPTER_KINDS + "])\\s*(\\d{1,4})(?:\\s*[-~]\\s*(\\d{1,4}))?");
    // 第X卷 / 第01话 / 第三册 / 第2章
    private static final Pattern ZH_PREFIXED = Pattern.compile(
            "第\\s*([0-9零一二三四五六七八九十百千万両两壹贰叁肆伍陆柒捌玖拾]+)\\s*"
                    + "([" + VOL_KINDS + EPISODE_KINDS + CHAPTER_KINDS + "])(?:\\s*[-~]\\s*(\\d{1,4}))?");
    // 英文：Vol.1 / Volume 2 / Ch.5 / Chapter 3 / EP.01 / Part 2 / Act 3 / Book 4 / Season 2
    private static final Pattern EN_KINDS = Pattern.compile(
            "\\b(?:vol\\.?|volume|ch\\.?|chapter|ep\\.?|episode|part|act|book|season)\\s*(\\d{1,4})",
            Pattern.CASE_INSENSITIVE);
    // S01E02
    private static final Pattern SEASON_EP = Pattern.compile("\\bs(\\d{1,3})\\s*e(\\d{1,3})\\b",
            Pattern.CASE_INSENSITIVE);
    // 季号信号：s+/数字必须前后不紧邻字母或数字，否则 "Class1"、"Boss2"、"Windows10" 里的
    // "s1"/"s2"/"s10" 会被当成季号，目录树凭空多出一层季节点，来源排序也跟着走偏。
    // 位数上限 3 与排序键 "s%03de%06d" 的定宽一致，超出会让字典序失去可比性。
    private static final Pattern SEASON_TOKEN = Pattern.compile(
            "(?<![A-Za-z0-9])s(\\d{1,3})(?:\\s*e\\d{1,3})?(?![A-Za-z0-9])"
                    + "|(?<![A-Za-z0-9])season\\s*(\\d{1,3})(?![A-Za-z0-9])"
                    + "|第\\s*([0-9零一二三四五六七八九十百千万両两壹贰叁肆伍陆柒捌玖拾]+)\\s*季",
            Pattern.CASE_INSENSITIVE);

    /**
     * 安全剥离真实扩展名。
     *
     * <p>只去掉"点 + 以字母开头的后缀"：以点加数字结尾（"Vol.1"、"第2期.3"）是分卷编号的一部分，
     * 无条件去掉最后一段会把 "Vol.1" 削成 "Vol"，卷号与聚合节点一起丢失。
     *
     * @param fileName 文件名（含或不含扩展名均可）
     * @return 剥离扩展名后的名称；入参为空时返回空串
     */
    public static String stripExtension(String fileName) {
        if (fileName == null || fileName.isBlank()) {
            return "";
        }
        return fileName.replaceFirst("\\.[A-Za-z][A-Za-z0-9]{0,9}$", "");
    }

    /**
     * 解析文件名中的分卷信息。
     *
     * @param fileName 文件名（含或不含扩展名均可）
     * @return 解析结果；未识别到任何分卷信号时 matched=false
     */
    public static PartInfo parse(String fileName) {
        if (fileName == null || fileName.isBlank()) {
            return new PartInfo(null, null, null, false);
        }
        String name = stripExtension(fileName);

        // 季集：S01E02 优先级最高
        Matcher se = SEASON_EP.matcher(name);
        if (se.find()) {
            return new PartInfo("SEASON_EP", Integer.parseInt(se.group(1)),
                    Integer.parseInt(se.group(2)), true);
        }

        // 英文分卷/话
        Matcher en = EN_KINDS.matcher(name);
        if (en.find()) {
            String token = en.group(0).toLowerCase(Locale.ROOT);
            String kind;
            if (token.startsWith("vol") || token.startsWith("part")
                    || token.startsWith("act") || token.startsWith("book")) {
                kind = "VOL";
            } else if (token.startsWith("season")) {
                kind = "SEASON";
            } else {
                kind = "EPISODE";
            }
            return new PartInfo(kind, Integer.parseInt(en.group(1)), null, true);
        }

        // 中文前缀式：第X卷 / 第三册 / 第2章
        Matcher zh = ZH_PREFIXED.matcher(name);
        if (zh.find()) {
            String kind = kindOf(zh.group(2));
            Integer start = parseNumber(zh.group(1));
            Integer end = zh.group(3) != null ? Integer.parseInt(zh.group(3)) : null;
            return new PartInfo(kind, start, end, true);
        }

        // 前缀式：卷01 / 話001-010 / 第2话 之后的纯"卷01"形态
        Matcher prefixed = PREFIXED.matcher(name);
        if (prefixed.find()) {
            String kind = kindOf(prefixed.group(1));
            Integer end = prefixed.group(3) != null ? Integer.parseInt(prefixed.group(3)) : null;
            return new PartInfo(kind, Integer.parseInt(prefixed.group(2)), end, true);
        }

        // 纯数字区间（如 001-010）作为话信号兜底
        Matcher range = Pattern.compile("(\\d{2,4})\\s*[-~]\\s*(\\d{2,4})").matcher(name);
        if (range.find()) {
            return new PartInfo("EPISODE", Integer.parseInt(range.group(1)),
                    Integer.parseInt(range.group(2)), true);
        }

        return new PartInfo(null, null, null, false);
    }

    /**
     * 判断文件名是否包含分卷信号。
     *
     * @param fileName 文件名
     * @return true 表示包含分卷信号
     */
    public static boolean hasPartSignal(String fileName) {
        return parse(fileName).matched();
    }

    /**
     * 从文件名中提取季号（S01 / S01E02 / Season 1 / 第1季 / 第一季）。
     *
     * <p>目录聚合与来源排序都用这一个判据，避免各写一份窄正则时把发布者标签里的
     * "s+数字" 也认成季号。
     *
     * @param fileName 文件名（含或不含扩展名均可）
     * @return 季号；未识别到季号信号时返回 null
     */
    public static Integer parseSeasonNo(String fileName) {
        if (fileName == null || fileName.isBlank()) {
            return null;
        }
        Matcher matcher = SEASON_TOKEN.matcher(stripExtension(fileName));
        if (!matcher.find()) {
            return null;
        }
        if (matcher.group(1) != null) {
            return Integer.parseInt(matcher.group(1));
        }
        if (matcher.group(2) != null) {
            return Integer.parseInt(matcher.group(2));
        }
        return parseNumber(matcher.group(3));
    }

    /**
     * 清洗书名：去除发布者标签与分卷后缀，得到干净的系列名。
     *
     * @param title 原始书名/文件名
     * @return 清洗后的系列名
     */
    public static String normalizeTitle(String title) {
        if (title == null || title.isBlank()) {
            return "";
        }
        String result = title.trim();
        // 剥离中文分卷后缀：第X卷/话/册/章...
        result = result.replaceAll("第\\s*[0-9零一二三四五六七八九十百千万両两壹贰叁肆伍陆柒捌玖拾]+\\s*["
                + VOL_KINDS + EPISODE_KINDS + CHAPTER_KINDS + "].*$", "");
        // 剥离前缀式分卷：卷01 / 話001-010 / 001-010
        result = result.replaceAll("[" + VOL_KINDS + EPISODE_KINDS + CHAPTER_KINDS + "]\\s*\\d{1,4}.*$", "");
        result = result.replaceAll("\\s*\\d{2,4}\\s*[-~]\\s*\\d{2,4}\\s*$", "");
        // 英文分卷后缀
        result = result.replaceAll("(?i)\\s*(?:vol\\.?|volume|ch\\.?|chapter|ep\\.?|episode|part|act|book)\\s*\\d+.*$", "");
        result = result.replaceAll("(?i)\\s*s\\d+\\s*e\\d+\\s*$", "");
        // 剥离发布者前缀标签：仅当后面还有括号组时才剥离，保留系列名括号组
        result = result.replaceAll("^(?:\\[[^\\]]*\\]\\s*)+(?=\\[)", "");
        // 解包剩余的单一系列名括号组： [紹宋] → 紹宋
        result = result.replaceAll("^\\s*\\[|\\]\\s*$", "");
        // 去除尾部空白与分隔符
        result = result.replaceAll("[\\s_\\-\\[\\]]+$", "");
        return result.trim();
    }

    private static String kindOf(String kind) {
        if (VOL_KINDS.indexOf(kind) >= 0) {
            return "VOL";
        }
        if (EPISODE_KINDS.indexOf(kind) >= 0) {
            return "EPISODE";
        }
        return "CHAPTER";
    }

    /**
     * 阿拉伯或中文数字转阿拉伯数字；不支持时返回 null。
     *
     * <p>中文数字统一走 {@link ReaderTextParser#chineseNumberValue}：这里曾有另一份实现，
     * 把"十一"算成 -9、"二十"算成 -8，分卷排序与目录跟着一起错。
     */
    private static Integer parseNumber(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        if (value.matches("\\d+")) {
            try {
                return Integer.parseInt(value);
            } catch (NumberFormatException exception) {
                return null;
            }
        }
        int parsed = ReaderTextParser.chineseNumberValue(value);
        return parsed < 0 ? null : parsed;
    }
}
