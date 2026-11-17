package com.omninest.modules.video.domain;

/**
 * 媒体库扫描类型。每种类型使用独立的分类规则，禁止把剧集文件回退为电影。
 */
public enum MediaLibraryType {
    MOVIE,
    TV_SERIES,
    ANIME,
    /**
     * 混合根来源。根来源按第一级目录（Anime、Movie、TV Series）选择分类器，
     * 不会把宿主机绝对路径暴露给业务层。
     */
    ROOT
}
