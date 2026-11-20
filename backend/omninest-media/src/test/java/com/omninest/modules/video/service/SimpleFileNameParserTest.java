package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * 文件名解析回归矩阵：重点守住「第X部」、含年份片名与技术标签三类误判。
 *
 * @author OmniNest
 */
class SimpleFileNameParserTest {

    private final SimpleFileNameParser parser = new SimpleFileNameParser();

    @Test
    void partNumberAloneStaysAMovieTitle() {
        FileNameGuess guess = parser.parse("封神第一部.2023.2160p.BluRay.x265.mkv");

        assertThat(guess.title()).isEqualTo("封神第一部");
        assertThat(guess.year()).isEqualTo(2023);
        assertThat(guess.seasonNumber()).isNull();
        assertThat(guess.episodeNumber()).isNull();
    }

    @Test
    void yearPrefixedTitleIsNotTruncated() {
        FileNameGuess first = parser.parse("1917.2019.1080p.BluRay.mkv");

        assertThat(first.title()).isEqualTo("1917");
        assertThat(first.year()).isEqualTo(2019);
        assertThat(first.seasonNumber()).isNull();
        assertThat(first.episodeNumber()).isNull();

        FileNameGuess second = parser.parse("2001太空漫游.1968.2160p.mkv");

        assertThat(second.title()).isEqualTo("2001太空漫游");
        assertThat(second.year()).isEqualTo(1968);
        assertThat(second.seasonNumber()).isNull();
        assertThat(second.episodeNumber()).isNull();
    }

    @Test
    void technicalTagsAreNotTreatedAsEpisodeNumbers() {
        FileNameGuess guess = parser.parse("三体.第1季.2023.60fps.10bit.mkv");

        assertThat(guess.title()).isEqualTo("三体");
        assertThat(guess.year()).isEqualTo(2023);
        assertThat(guess.seasonNumber()).isEqualTo(1);
        assertThat(guess.episodeNumber()).isNull();
    }

    @Test
    void partWithExplicitEpisodeBecomesASeries() {
        FileNameGuess guess = parser.parse("仙剑奇侠传.第一部.第01集.1080p.mkv");

        assertThat(guess.title()).isEqualTo("仙剑奇侠传");
        assertThat(guess.seasonNumber()).isEqualTo(1);
        assertThat(guess.episodeNumber()).isEqualTo(1);
    }

    @Test
    void directoryNameWithSeasonIsRecognized() {
        FileNameGuess guess = parser.parse("权力的游戏 第一季");

        assertThat(guess.title()).isEqualTo("权力的游戏");
        assertThat(guess.seasonNumber()).isEqualTo(1);
        assertThat(guess.episodeNumber()).isNull();
    }

    @Test
    void westernSeasonEpisodeFormatIsPreserved() {
        FileNameGuess guess = parser.parse(
                "仙剑奇侠传.Chinese.Paladin.S01E01.2005.2160p.WEB-DL.H265.10bit.AAC.mkv");

        assertThat(guess.title()).isEqualTo("仙剑奇侠传 Chinese Paladin");
        assertThat(guess.year()).isEqualTo(2005);
        assertThat(guess.seasonNumber()).isEqualTo(1);
        assertThat(guess.episodeNumber()).isEqualTo(1);
    }

    @Test
    void ordinaryMoviesRemainMovies() {
        FileNameGuess first = parser.parse("第二十条.2024.HD1080p.mkv");
        FileNameGuess second = parser.parse("流浪地球2.2023.1080p.mkv");

        assertThat(first.title()).isEqualTo("第二十条");
        assertThat(first.year()).isEqualTo(2024);
        assertThat(first.seasonNumber()).isNull();
        assertThat(second.title()).isEqualTo("流浪地球2");
        assertThat(second.year()).isEqualTo(2023);
        assertThat(second.seasonNumber()).isNull();
    }
}
