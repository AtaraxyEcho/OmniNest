package com.omninest.modules.photos.repository;

/**
 * 照片分组分页使用的预览投影。
 *
 * @author OmniNest
 */
public interface PhotoGroupPreviewProjection extends PhotoListItemProjection {

    /** @return 分组键 */
    String getGroupKey();

    /** @return 当前分组的照片总数 */
    long getPhotoCount();
}
