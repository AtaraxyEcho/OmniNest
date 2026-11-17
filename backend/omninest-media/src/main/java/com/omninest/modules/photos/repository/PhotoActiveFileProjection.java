package com.omninest.modules.photos.repository;

import java.util.UUID;

/**
 * 照片当前活动全分辨率文件的批量投影。
 *
 * <p>只覆盖已产生编辑产物的照片，未编辑照片不出现在结果中。</p>
 *
 * @author OmniNest
 */
public interface PhotoActiveFileProjection {

    /** @return 照片标识 */
    UUID getPhotoId();

    /** @return 当前活动文件节点标识 */
    UUID getActiveFileId();
}
