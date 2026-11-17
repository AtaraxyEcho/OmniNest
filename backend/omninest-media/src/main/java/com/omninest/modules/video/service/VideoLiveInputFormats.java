package com.omninest.modules.video.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * 实时播放允许的输入容器与对应 demuxer。
 *
 * <p>直播链路仍把预签名 HTTP 地址直接交给 ffmpeg（拖动进度条需要 Range 读取，无法整片落盘），
 * 因此不能让 ffmpeg 自行探测容器：HLS/DASH/播放列表等容器会继续解析文件内嵌的远程地址，
 * 后端容器同时有内网和公网出口。这里按扫描阶段已落库的 ffprobe 容器名强制指定 demuxer，
 * 未知或可内嵌引用的容器直接拒绝，不再进入自动探测。</p>
 *
 * @author OmniNest
 */
final class VideoLiveInputFormats {

    private static final Map<String, String> DEMUXERS = Map.ofEntries(
            Map.entry("mov", "mov"),
            Map.entry("mp4", "mov"),
            Map.entry("m4a", "mov"),
            Map.entry("3gp", "mov"),
            Map.entry("3g2", "mov"),
            Map.entry("mj2", "mov"),
            Map.entry("matroska", "matroska"),
            Map.entry("webm", "matroska"),
            Map.entry("mpegts", "mpegts"),
            Map.entry("avi", "avi"),
            Map.entry("flv", "flv"),
            Map.entry("mpeg", "mpeg"),
            Map.entry("mpegps", "mpeg"),
            Map.entry("mpegvideo", "mpeg"),
            Map.entry("ogg", "ogg"),
            Map.entry("asf", "asf"),
            Map.entry("rm", "rm"),
            Map.entry("mxf", "mxf"),
            Map.entry("dv", "dv"),
            Map.entry("nut", "nut"),
            Map.entry("swf", "swf"),
            Map.entry("h264", "h264"),
            Map.entry("hevc", "hevc")
    );

    /**
     * 可引用外部资源的容器：即使同一 format_name 里混有普通容器名也必须拒绝。
     */
    private static final Set<String> EXTERNAL_REFERENCE_CONTAINERS = Set.of(
            "hls", "applehttp", "dash", "concat", "image2", "image2pipe", "ffconcat"
    );

    private VideoLiveInputFormats() {
    }

    /**
     * 解析容器名对应的 demuxer。
     *
     * @param containerFormat ffprobe 返回的 format_name，可能是逗号分隔的候选列表
     * @return 可安全自动探测的 demuxer 名称
     */
    static String requireDemuxer(String containerFormat) {
        if (containerFormat == null || containerFormat.isBlank()) {
            throw unsupported();
        }
        String[] tokens = containerFormat.toLowerCase(Locale.ROOT).split(",");
        for (String token : tokens) {
            String normalized = token.trim();
            if (EXTERNAL_REFERENCE_CONTAINERS.contains(normalized)) {
                throw unsupported();
            }
        }
        for (String token : tokens) {
            String demuxer = DEMUXERS.get(token.trim());
            if (demuxer != null) {
                return demuxer;
            }
        }
        throw unsupported();
    }

    private static BusinessException unsupported() {
        return new BusinessException(ErrorCode.MEDIA_FORMAT_UNSUPPORTED, "该媒体容器不支持安全流式播放");
    }
}
