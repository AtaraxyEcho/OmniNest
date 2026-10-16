package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.reader.config.ReaderArchiveLimitsProperties;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;

/**
 * 真书库元数据闸门。
 *
 * <p>语料是本机素材，只在显式传入 {@code -Dreader.corpus=<目录>} 时运行， CI 与本机缺少
 * 该目录时整组跳过。闸门锁的是"导入一本书时最先失败的那一步不能失败"：元数据解析返回
 * null 或 spine 为空的书，在业务侧一律是 400，整本进不了阅读页。
 *
 * <p>只列目录不递归：子目录里是漫画 EPUB，每页一个图片容器，spine 口径不同。
 *
 * @author OmniNest
 */
@EnabledIfSystemProperty(named = "reader.corpus", matches = ".+")
class ReaderEpubCorpusParseTest {

    @Test
    void everyCorpusEpubExposesReadableSpine() throws IOException {
        Path corpus = Path.of(System.getProperty("reader.corpus"));
        ReaderArchiveSafetyPolicy safetyPolicy = new ReaderArchiveSafetyPolicy(
                new ReaderArchiveLimitsProperties()
        );
        ComicEpubParser parser = new ComicEpubParser();
        List<String> failures = new ArrayList<>();
        int books = 0;

        for (Path epub : sortedEpubs(corpus)) {
            books++;
            try (EpubArchive archive = new EpubArchive(epub, safetyPolicy)) {
                ComicEpubParser.EpubParseResult metadata = parser.parseMetadata(archive);
                if (metadata == null) {
                    failures.add(epub.getFileName() + " -> 元数据解析失败");
                } else if (metadata.spine().isEmpty()) {
                    failures.add(epub.getFileName() + " -> spine 为空");
                }
            } catch (Exception exception) {
                failures.add(epub.getFileName() + " -> " + exception.getClass().getSimpleName());
            }
        }

        assertThat(books).as("语料中的 EPUB 数量").isPositive();
        assertThat(failures).as("元数据解析失败的书").isEmpty();
    }

    private List<Path> sortedEpubs(Path corpus) throws IOException {
        try (Stream<Path> entries = Files.list(corpus)) {
            return entries
                    .filter(path -> path.getFileName().toString().toLowerCase(Locale.ROOT).endsWith(".epub"))
                    .sorted()
                    .toList();
        }
    }
}
