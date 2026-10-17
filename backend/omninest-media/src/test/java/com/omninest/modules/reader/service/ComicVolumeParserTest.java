package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/**
 * 漫画分卷命名解析器测试。
 *
 * @author OmniNest
 */
class ComicVolumeParserTest {

    @Test
    void parsesEpisodesRange() {
        ComicVolumeParser.PartInfo part = ComicVolumeParser.parse("[Kmoe][紹宋]話001-010.epub");
        assertThat(part.matched()).isTrue();
        assertThat(part.partKind()).isEqualTo("EPISODE");
        assertThat(part.partNo()).isEqualTo(1);
        assertThat(part.rangeEnd()).isEqualTo(10);
    }

    @Test
    void parsesVolumePrefix() {
        ComicVolumeParser.PartInfo part = ComicVolumeParser.parse("[Kmoe][躲在超市後門抽煙的兩人]卷01.epub");
        assertThat(part.matched()).isTrue();
        assertThat(part.partKind()).isEqualTo("VOL");
        assertThat(part.partNo()).isEqualTo(1);
    }

    @Test
    void parsesTraditionalVolumeKanj() {
        ComicVolumeParser.PartInfo part = ComicVolumeParser.parse("[Kmoe][葬送的芙莉蓮]巻01.epub");
        assertThat(part.matched()).isTrue();
        assertThat(part.partKind()).isEqualTo("VOL");
        assertThat(part.partNo()).isEqualTo(1);
    }

    @Test
    void parsesChineseNumberVolume() {
        ComicVolumeParser.PartInfo part = ComicVolumeParser.parse("某漫画 第三卷.epub");
        assertThat(part.matched()).isTrue();
        assertThat(part.partKind()).isEqualTo("VOL");
        assertThat(part.partNo()).isEqualTo(3);
    }

    @Test
    void parsesMultiCharacterChineseNumbers() {
        // 数位-单位必须累加：另一份实现把"十"当成未知数字，算出 -9/-8 的卷号，
        // 排序与目录一起走偏。
        assertThat(ComicVolumeParser.parse("葬送的芙莉莲 第十一卷.cbz").partNo()).isEqualTo(11);
        assertThat(ComicVolumeParser.parse("葬送的芙莉莲 第二十卷.cbz").partNo()).isEqualTo(20);
        assertThat(ComicVolumeParser.parse("海贼王 第二十三话.cbz").partNo()).isEqualTo(23);
        assertThat(ComicVolumeParser.parse("海贼王 第一百零八话.cbz").partNo()).isEqualTo(108);
        assertThat(ComicVolumeParser.parse("某漫画 第十卷.cbz").partNo()).isEqualTo(10);
    }

    @Test
    void keepsVolumeNumberWhenTheNameEndsWithDotDigits() {
        // "Vol.1" 的 .1 是分卷号不是扩展名：无条件去掉最后一段会让卷号与合并信号一起消失，
        // 共享漫画的英文命名分卷因此永远并不进同一部作品。
        assertThat(ComicVolumeParser.parse("葬送的芙莉莲 Vol.1.cbz").partNo()).isEqualTo(1);
        assertThat(ComicVolumeParser.parse("葬送的芙莉莲 Vol.1").partNo()).isEqualTo(1);
        assertThat(ComicVolumeParser.hasPartSignal("葬送的芙莉莲 Vol.1")).isTrue();
        assertThat(ComicVolumeParser.parse("某漫画 第3卷.cbz").partNo()).isEqualTo(3);
    }

    @Test
    void parsesBookChapter() {
        ComicVolumeParser.PartInfo part = ComicVolumeParser.parse("某漫画 第2册.epub");
        assertThat(part.matched()).isTrue();
        assertThat(part.partKind()).isEqualTo("VOL");
        assertThat(part.partNo()).isEqualTo(2);
    }

    @Test
    void parsesEnglishVolume() {
        ComicVolumeParser.PartInfo part = ComicVolumeParser.parse("某漫画 Vol.1.epub");
        assertThat(part.matched()).isTrue();
        assertThat(part.partKind()).isEqualTo("VOL");
        assertThat(part.partNo()).isEqualTo(1);
    }

    @Test
    void parsesSeasonEpisode() {
        ComicVolumeParser.PartInfo part = ComicVolumeParser.parse("某动画 S01E02.cbz");
        assertThat(part.matched()).isTrue();
        assertThat(part.partKind()).isEqualTo("SEASON_EP");
        assertThat(part.partNo()).isEqualTo(1);
        assertThat(part.rangeEnd()).isEqualTo(2);
    }

    @Test
    void normalizesTitleStripsTagsAndPartSuffix() {
        assertThat(ComicVolumeParser.normalizeTitle("[Kmoe][紹宋]話001-010"))
                .isEqualTo("紹宋");
        assertThat(ComicVolumeParser.normalizeTitle("[Kmoe][躲在超市後門抽煙的兩人]卷01"))
                .isEqualTo("躲在超市後門抽煙的兩人");
        assertThat(ComicVolumeParser.normalizeTitle("某漫画 第1卷"))
                .isEqualTo("某漫画");
    }

    @Test
    void noPartSignalForPlainTitle() {
        assertThat(ComicVolumeParser.hasPartSignal("白夜")).isFalse();
        assertThat(ComicVolumeParser.parse("白夜").matched()).isFalse();
    }

    @Test
    void stripsOnlyRealExtension() {
        assertThat(ComicVolumeParser.stripExtension("作品 001-010.cbz")).isEqualTo("作品 001-010");
        assertThat(ComicVolumeParser.stripExtension("葬送的芙莉莲 Vol.1")).isEqualTo("葬送的芙莉莲 Vol.1");
        assertThat(ComicVolumeParser.stripExtension("白夜")).isEqualTo("白夜");
        assertThat(ComicVolumeParser.stripExtension(null).isEmpty()).isTrue();
    }

    @Test
    void seasonNeedsTokenBoundaries() {
        assertThat(ComicVolumeParser.parseSeasonNo("某动画 S01E02.cbz")).isEqualTo(1);
        assertThat(ComicVolumeParser.parseSeasonNo("某动画 _S02_ 第03话.cbz")).isEqualTo(2);
        assertThat(ComicVolumeParser.parseSeasonNo("某动画 Season 3.cbz")).isEqualTo(3);
        assertThat(ComicVolumeParser.parseSeasonNo("某动画 第十一季.cbz")).isEqualTo(11);
        assertThat(ComicVolumeParser.parseSeasonNo("某动画 S100.cbz")).isEqualTo(100);
        assertThat(ComicVolumeParser.parseSeasonNo("Class1 Vol.1.cbz")).isNull();
        assertThat(ComicVolumeParser.parseSeasonNo("Boss2 第01话.cbz")).isNull();
        assertThat(ComicVolumeParser.parseSeasonNo("Windows10 第1卷.cbz")).isNull();
        assertThat(ComicVolumeParser.parseSeasonNo("白夜")).isNull();
    }

    @Test
    void threeDigitSeasonEpisodeStillParses() {
        ComicVolumeParser.PartInfo part = ComicVolumeParser.parse("某动画 S100E005.cbz");
        assertThat(part.matched()).isTrue();
        assertThat(part.partKind()).isEqualTo("SEASON_EP");
        assertThat(part.partNo()).isEqualTo(100);
        assertThat(part.rangeEnd()).isEqualTo(5);
    }
}
