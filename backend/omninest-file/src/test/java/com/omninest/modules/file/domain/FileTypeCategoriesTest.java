package com.omninest.modules.file.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class FileTypeCategoriesTest {

    @Test
    void resolvesComicAndNovelByExtensionEvenWhenMimeIsArchiveOrGeneric() {
        assertThat(FileTypeCategories.resolve("chapter.cbz", "application/zip", "FILE"))
                .isEqualTo(FileTypeCategories.COMIC);
        assertThat(FileTypeCategories.resolve("book.azw3", "application/octet-stream", "FILE"))
                .isEqualTo(FileTypeCategories.NOVEL);
        assertThat(FileTypeCategories.resolve("backup.zip", "application/zip", "FILE"))
                .isEqualTo(FileTypeCategories.ARCHIVE);
    }

    @Test
    void resolvesCommonMediaByExtensionWhenMimeIsGeneric() {
        assertThat(FileTypeCategories.resolve("cover.jpg", "application/octet-stream", "FILE"))
                .isEqualTo(FileTypeCategories.IMAGE);
        assertThat(FileTypeCategories.resolve("clip.mkv", "application/octet-stream", "FILE"))
                .isEqualTo(FileTypeCategories.VIDEO);
        assertThat(FileTypeCategories.resolve("song.mp3", "application/octet-stream", "FILE"))
                .isEqualTo(FileTypeCategories.AUDIO);
        assertThat(FileTypeCategories.resolve("report.pdf", "application/octet-stream", "FILE"))
                .isEqualTo(FileTypeCategories.DOCUMENT);
    }

    @Test
    void resolvesByMimePrefixAndReturnsNullForNonFile() {
        assertThat(FileTypeCategories.resolve("noext", "video/mp4", "FILE"))
                .isEqualTo(FileTypeCategories.VIDEO);
        assertThat(FileTypeCategories.resolve("x.bin", "application/octet-stream", "FILE"))
                .isEqualTo(FileTypeCategories.OTHER);
        assertThat(FileTypeCategories.resolve("Media", null, "FOLDER")).isNull();
    }
}
