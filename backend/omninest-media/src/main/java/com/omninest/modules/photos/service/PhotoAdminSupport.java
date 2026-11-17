package com.omninest.modules.photos.service;

import com.omninest.modules.photos.domain.PhotoScanJob;
import com.omninest.modules.photos.dto.PhotoDtos.PhotoScanJobDto;

/**
 * 照片扫描的进度、摘要与 DTO 装配辅助方法。
 *
 * @author OmniNest
 */
final class PhotoAdminSupport {

    private PhotoAdminSupport() {
    }

    static int progressPercent(int finished, int total) {
        if (total <= 0) {
            return 100;
        }
        return Math.min(100, (int) Math.round(finished * 100.0 / total));
    }

    static String titleFromFileName(String fileName) {
        String name = fileName == null ? "Untitled" : fileName.trim();
        int dotIndex = name.lastIndexOf('.');
        return dotIndex <= 0 ? name : name.substring(0, dotIndex);
    }

    static PhotoScanJobDto toDto(PhotoScanJob job) {
        return new PhotoScanJobDto(
                job.getId(),
                job.getStatus(),
                job.getScannedFiles(),
                job.getMessage(),
                job.getCreatedAt(),
                job.getUpdatedAt()
        );
    }
}
