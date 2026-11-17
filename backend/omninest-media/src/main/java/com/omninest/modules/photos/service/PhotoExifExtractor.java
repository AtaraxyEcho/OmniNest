package com.omninest.modules.photos.service;

import com.drew.imaging.ImageMetadataReader;
import com.drew.lang.annotations.Nullable;
import com.drew.metadata.Directory;
import com.drew.metadata.Metadata;
import com.drew.metadata.exif.ExifDirectoryBase;
import com.drew.metadata.exif.ExifIFD0Directory;
import com.drew.metadata.exif.ExifSubIFDDirectory;
import com.drew.metadata.exif.GpsDirectory;
import com.drew.metadata.xmp.XmpDirectory;
import java.io.InputStream;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Date;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class PhotoExifExtractor {

    /**
     * 动态照片（Motion Photo）XMP 检测结果。
     *
     * @param motionPhoto GCamera 新标准标记（MotionPhoto=true）
     * @param microVideo GCamera 旧标准标记（MicroVideo=1）
     * @param microVideoOffset 旧标准的视频起点距文件末尾字节数；新标准通常无此值
     */
    public record MotionInfo(
            boolean motionPhoto,
            boolean microVideo,
            @Nullable Long microVideoOffset
    ) {
        public boolean detected() {
            return motionPhoto || microVideo;
        }
    }

    public record ExifData(
            Integer width,
            Integer height,
            Integer orientation,
            Instant dateTaken,
            String cameraMake,
            String cameraModel,
            String aperture,
            String shutterSpeed,
            Integer iso,
            String focalLength,
            String flash,
            String whiteBalance,
            String meteringMode,
            String lensModel,
            BigDecimal gpsLatitude,
            BigDecimal gpsLongitude,
            Map<String, Object> rawMetadata,
            MotionInfo motion
    ) {
        public static ExifData empty() {
            return new ExifData(null, null, null, null, null, null, null, null, null, null,
                    null, null, null, null, null, null, Map.of(), new MotionInfo(false, false, null));
        }

        public boolean hasAnyValue() {
            return width != null || height != null || dateTaken != null
                    || cameraMake != null || cameraModel != null
                    || flash != null || whiteBalance != null
                    || meteringMode != null || lensModel != null;
        }
    }

    /**
     * 从图片输入流中提取 EXIF 元数据。
     */
    public ExifData extract(InputStream stream) {
        try {
            Metadata metadata = ImageMetadataReader.readMetadata(stream);
            Map<String, Object> raw = new HashMap<>();

            ExifIFD0Directory ifd0 = metadata.getFirstDirectoryOfType(ExifIFD0Directory.class);
            ExifSubIFDDirectory subIfd = metadata.getFirstDirectoryOfType(ExifSubIFDDirectory.class);
            GpsDirectory gps = metadata.getFirstDirectoryOfType(GpsDirectory.class);

            Integer width = safeGetInt(subIfd, ExifSubIFDDirectory.TAG_EXIF_IMAGE_WIDTH);
            if (width == null) width = safeGetInt(subIfd, ExifDirectoryBase.TAG_IMAGE_WIDTH);
            Integer height = safeGetInt(subIfd, ExifSubIFDDirectory.TAG_EXIF_IMAGE_HEIGHT);
            if (height == null) height = safeGetInt(subIfd, ExifDirectoryBase.TAG_IMAGE_HEIGHT);

            Integer orientation = safeGetInt(ifd0, ExifIFD0Directory.TAG_ORIENTATION);

            Instant dateTaken = null;
            if (subIfd != null) {
                Date date = subIfd.getDate(ExifSubIFDDirectory.TAG_DATETIME_ORIGINAL);
                if (date != null) dateTaken = date.toInstant();
            }
            if (dateTaken == null && ifd0 != null) {
                Date date = ifd0.getDate(ExifIFD0Directory.TAG_DATETIME);
                if (date != null) dateTaken = date.toInstant();
            }

            String cameraMake = ifd0 != null ? ifd0.getString(ExifIFD0Directory.TAG_MAKE) : null;
            String cameraModel = ifd0 != null ? ifd0.getString(ExifIFD0Directory.TAG_MODEL) : null;

            String aperture = null;
            String shutterSpeed = null;
            Integer iso = null;
            String focalLength = null;
            if (subIfd != null) {
                aperture = subIfd.getString(ExifSubIFDDirectory.TAG_FNUMBER);
                shutterSpeed = subIfd.getString(ExifSubIFDDirectory.TAG_EXPOSURE_TIME);
                iso = safeGetInt(subIfd, ExifSubIFDDirectory.TAG_ISO_EQUIVALENT);
                focalLength = subIfd.getString(ExifSubIFDDirectory.TAG_FOCAL_LENGTH);
            }

            String flash = null;
            String whiteBalance = null;
            String meteringMode = null;
            String lensModel = null;
            if (subIfd != null) {
                flash = subIfd.getString(ExifSubIFDDirectory.TAG_FLASH);
                whiteBalance = subIfd.getString(ExifSubIFDDirectory.TAG_WHITE_BALANCE);
                meteringMode = subIfd.getString(ExifSubIFDDirectory.TAG_METERING_MODE);
                lensModel = subIfd.getString(ExifSubIFDDirectory.TAG_LENS_MODEL);
            }

            BigDecimal gpsLat = null;
            BigDecimal gpsLon = null;
            if (gps != null && gps.getGeoLocation() != null) {
                gpsLat = BigDecimal.valueOf(gps.getGeoLocation().getLatitude());
                gpsLon = BigDecimal.valueOf(gps.getGeoLocation().getLongitude());
            }

            return new ExifData(width, height, orientation, dateTaken,
                    cameraMake, cameraModel, aperture, shutterSpeed,
                    iso, focalLength, flash, whiteBalance, meteringMode, lensModel,
                    gpsLat, gpsLon, raw, extractMotionInfo(metadata));
        } catch (Exception ex) {
            log.warn("EXIF 提取失败: {}", ex.getMessage());
            return ExifData.empty();
        }
    }

    private Integer safeGetInt(Directory dir, int tagType) {
        if (dir == null || !dir.containsTag(tagType)) {
            return null;
        }
        try {
            return dir.getInt(tagType);
        } catch (Exception ex) {
            log.debug("EXIF 整型读取失败: tagType={}, message={}", tagType, ex.getMessage());
            return null;
        }
    }

    /**
     * 从 XMP 目录解析动态照片标记（GCamera 新旧标准）。
     *
     * <p>XmpDirectory 会把所有命名空间属性平铺为字符串键值；三星新固件同样写入
     * GCamera 标记，老固件的纯 SEF trailer 由文件尾部扫描单独兜底。</p>
     */
    MotionInfo extractMotionInfo(Metadata metadata) {
        XmpDirectory xmp = metadata.getFirstDirectoryOfType(XmpDirectory.class);
        if (xmp == null) {
            return new MotionInfo(false, false, null);
        }
        try {
            Map<String, String> properties = xmp.getXmpProperties();
            if (properties == null || properties.isEmpty()) {
                return new MotionInfo(false, false, null);
            }
            boolean motionPhoto = parseBooleanFlag(properties.get("GCamera:MotionPhoto"));
            boolean microVideo = parseBooleanFlag(properties.get("GCamera:MicroVideo"));
            Long offset = null;
            String rawOffset = properties.get("GCamera:MicroVideoOffset");
            if (rawOffset != null && !rawOffset.isBlank()) {
                try {
                    long parsed = Long.parseLong(rawOffset.trim());
                    if (parsed > 0) {
                        offset = parsed;
                    }
                } catch (NumberFormatException ex) {
                    log.debug("MicroVideoOffset 解析失败: {}", rawOffset);
                }
            }
            return new MotionInfo(motionPhoto, microVideo, offset);
        } catch (Exception ex) {
            log.warn("XMP 动态照片标记解析失败: {}", ex.getMessage());
            return new MotionInfo(false, false, null);
        }
    }

    private boolean parseBooleanFlag(String value) {
        if (value == null) {
            return false;
        }
        String normalized = value.trim().toLowerCase(Locale.ROOT);
        return "true".equals(normalized) || "1".equals(normalized);
    }
}
