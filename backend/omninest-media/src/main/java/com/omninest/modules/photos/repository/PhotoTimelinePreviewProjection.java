package com.omninest.modules.photos.repository;

/**
 * 照片时间线月份分页使用的预览投影。
 *
 * @author OmniNest
 */
public interface PhotoTimelinePreviewProjection extends PhotoListItemProjection {

    /** @return 照片拍摄年份 */
    int getYear();

    /** @return 照片拍摄月份 */
    int getMonth();

    /** @return 当前月份的照片总数 */
    long getPhotoCount();
}
