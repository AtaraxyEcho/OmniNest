package com.omninest.common.messaging;

import java.util.List;

/**
 * RabbitMQ 交换机、队列和路由键常量。
 *
 * @author OmniNest
 */
public final class QueueNames {
    public static final String CONFIG_REFRESH_EXCHANGE = "omni.config";
    public static final String SYNC_EVENT_EXCHANGE = "omni.event";
    public static final String SYNC_EVENT_ROUTING_PATTERN = "sync.user.#";
    public static final String NOTIFICATION_EVENT_EXCHANGE = "omni.notification";
    public static final String TASK_EXCHANGE = "omni.task";
    public static final String FILE_INDEX_QUEUE = "omni.task.file-index";
    public static final String FILE_INDEX_ROUTING_KEY = "file.index";
    public static final String FILE_RESTORE_INDEX_QUEUE = "omni.task.file-restore-index";
    public static final String FILE_RESTORE_INDEX_ROUTING_KEY = "file.restore.index";
    public static final String MEDIA_AUTO_IMPORT_QUEUE = "omni.task.media-auto-import";
    public static final String MEDIA_AUTO_IMPORT_ROUTING_KEY = "media.auto-import";
    public static final String TEXT_EXTRACTION_QUEUE = "omni.task.text-extraction";
    public static final String TEXT_EXTRACTION_ROUTING_KEY = "text.extract";
    public static final String MEDIA_QUEUE = "omni.task.media";
    public static final String MEDIA_SCRAPE_ROUTING_KEY = "media.scrape";
    public static final String OFFLINE_DOWNLOAD_QUEUE = "omni.task.offline-download";
    public static final String OFFLINE_DOWNLOAD_ROUTING_KEY = "offline.download";
    public static final String VIDEO_TRANSCODE_QUEUE = "omni.task.video-transcode";
    public static final String VIDEO_TRANSCODE_ROUTING_KEY = "video.transcode";
    public static final String LOCAL_VIDEO_LIBRARY_SCAN_QUEUE = "omni.task.local-video-library-scan";
    public static final String LOCAL_VIDEO_LIBRARY_SCAN_ROUTING_KEY = "video.local-library.scan";
    public static final String LOCAL_VIDEO_LIBRARY_APPLY_QUEUE = "omni.task.local-video-library-apply";
    public static final String LOCAL_VIDEO_LIBRARY_APPLY_ROUTING_KEY = "video.local-library.apply";
    public static final String EXTERNAL_IMPORT_QUEUE = "omni.task.external-import";
    public static final String EXTERNAL_IMPORT_ROUTING_KEY = "external.import";
    public static final String MUSIC_SCAN_QUEUE = "omni.task.music-scan";
    public static final String MUSIC_SCAN_ROUTING_KEY = "music.scan";
    public static final String MUSIC_SCRAPE_QUEUE = "omni.task.music-scrape";
    public static final String MUSIC_SCRAPE_ROUTING_KEY = "music.scrape";
    public static final String THUMBNAIL_QUEUE = "omni.task.thumbnail";
    public static final String THUMBNAIL_ROUTING_KEY = "thumbnail.generate";
    public static final String PHOTO_SCAN_QUEUE = "omni.task.photo-scan";
    public static final String PHOTO_SCAN_ROUTING_KEY = "photo.scan";
    public static final String PHOTO_THUMBNAILS_QUEUE = "omni.task.photo-thumbnails";
    public static final String PHOTO_THUMBNAILS_ROUTING_KEY = "photo.thumbnails";
    public static final String PHOTO_INDEX_QUEUE = "omni.task.photo-index";
    public static final String PHOTO_INDEX_ROUTING_KEY = "photo.index";
    public static final String PHOTO_BATCH_QUEUE = "omni.task.photo-batch";
    public static final String PHOTO_BATCH_ROUTING_KEY = "photo.batch";
    public static final String PHOTO_AI_QUEUE = "omni.task.photo-ai";
    public static final String PHOTO_AI_ROUTING_KEY = "photo.ai";
    public static final String PHOTO_GEO_IMPORT_QUEUE = "omni.task.photo-geo-import";
    public static final String PHOTO_GEO_IMPORT_ROUTING_KEY = "photo.geo.import";
    public static final String PHOTO_GEO_BACKFILL_QUEUE = "omni.task.photo-geo-backfill";
    public static final String PHOTO_GEO_BACKFILL_ROUTING_KEY = "photo.geo.backfill";
    public static final String PHOTO_MOTION_QUEUE = "omni.task.photo-motion";
    public static final String PHOTO_MOTION_ROUTING_KEY = "photo.motion.extract";
    public static final String PHOTO_MOTION_RESCAN_QUEUE = "omni.task.photo-motion-rescan";
    public static final String PHOTO_MOTION_RESCAN_ROUTING_KEY = "photo.motion.rescan";
    public static final String DEAD_LETTER_EXCHANGE = "omni.dlx";
    public static final String DEAD_LETTER_QUEUE = "omni.dlx.dead-letter";
    public static final String DEAD_LETTER_ROUTING_KEY = "dead-letter";
    public static final String COMIC_PARSE_QUEUE = "omni.task.comic-parse";
    public static final String COMIC_PARSE_ROUTING_KEY = "comic.parse";
    public static final String READER_PARSE_QUEUE = "omni.task.reader-parse";
    public static final String READER_PARSE_ROUTING_KEY = "reader.parse";
    public static final String FILE_PURGE_QUEUE = "omni.task.file-purge";
    public static final String FILE_PURGE_ROUTING_KEY = "file.purge";

    private static final List<String> DURABLE_QUEUES = List.of(
            FILE_INDEX_QUEUE,
            FILE_RESTORE_INDEX_QUEUE,
            MEDIA_AUTO_IMPORT_QUEUE,
            TEXT_EXTRACTION_QUEUE,
            MEDIA_QUEUE,
            OFFLINE_DOWNLOAD_QUEUE,
            VIDEO_TRANSCODE_QUEUE,
            LOCAL_VIDEO_LIBRARY_SCAN_QUEUE,
            LOCAL_VIDEO_LIBRARY_APPLY_QUEUE,
            EXTERNAL_IMPORT_QUEUE,
            MUSIC_SCAN_QUEUE,
            MUSIC_SCRAPE_QUEUE,
            THUMBNAIL_QUEUE,
            PHOTO_SCAN_QUEUE,
            PHOTO_INDEX_QUEUE,
            PHOTO_BATCH_QUEUE,
            PHOTO_AI_QUEUE,
            PHOTO_GEO_IMPORT_QUEUE,
            PHOTO_GEO_BACKFILL_QUEUE,
            PHOTO_MOTION_QUEUE,
            PHOTO_MOTION_RESCAN_QUEUE,
            COMIC_PARSE_QUEUE,
            READER_PARSE_QUEUE,
            FILE_PURGE_QUEUE,
            DEAD_LETTER_QUEUE
    );

    /**
     * 返回需要监控积压的持久队列名称。
     *
     * @return 不可变持久队列列表
     */
    public static List<String> durableQueues() {
        return DURABLE_QUEUES;
    }

    private QueueNames() {
    }
}
