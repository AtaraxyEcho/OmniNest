package com.omninest.modules.photos.repository;

import java.util.UUID;

/**
 * 相册首张有效照片封面文件的批量投影。
 *
 * @author OmniNest
 */
public interface PhotoAlbumFirstCoverProjection {

    /** @return 相册标识 */
    UUID getAlbumId();

    /** @return 首张有效照片的封面文件标识 */
    UUID getCoverFileId();
}
