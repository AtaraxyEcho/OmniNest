package com.omninest.modules.music.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.dto.FileContentRange;
import com.omninest.modules.file.dto.FileContentStream;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.service.FileMetadataQueryService;
import com.omninest.modules.file.service.FilePlaybackContentService;
import com.omninest.modules.music.domain.MusicTrack;
import com.omninest.modules.music.repository.MusicTrackRepository;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.context.request.async.AsyncRequestNotUsableException;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

/**
 * 音乐播放流网关。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicStreamGatewayService {
    private static final int MAX_REDIRECT_COUNT = 5;
    private static final int BUFFER_SIZE = 16 * 1024;
    private static final Duration CONNECT_TIMEOUT = Duration.ofSeconds(8);
    private static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(30);

    private final MusicPlaybackSessionService sessionService;
    private final MusicOnlineSourceUrlPolicy sourceUrlPolicy;
    private final MusicTrackRepository trackRepository;
    private final FilePlaybackContentService filePlaybackContentService;
    private final FileMetadataQueryService fileMetadataQueryService;
    private final HttpClient httpClient = HttpClient.newBuilder()
            .connectTimeout(CONNECT_TIMEOUT)
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    /**
     * 输出播放会话对应的音频流。
     *
     * @param sessionId 会话标识
     * @param token 播放令牌
     * @param range Range 请求头
     * @param headRequest 是否为 HEAD 探测请求
     * @return 音频流响应
     */
    public ResponseEntity<StreamingResponseBody> stream(
            String sessionId,
            String token,
            String range,
            boolean headRequest
    ) {
        return sessionService.resolve(sessionId, token)
                .map(session -> streamResolvedSession(session, range, headRequest))
                .orElseGet(() -> ResponseEntity.status(HttpStatus.UNAUTHORIZED).build());
    }

    private ResponseEntity<StreamingResponseBody> streamResolvedSession(
            MusicPlaybackSession session,
            String range,
            boolean headRequest
    ) {
        if (session.sourceType() == MusicPlaybackSourceType.LOCAL) {
            return streamLocalSession(session, range, headRequest);
        }
        HttpResponse<InputStream> upstreamResponse = null;
        try {
            upstreamResponse = sendWithRedirects(session, range);
            if (headRequest) {
                // HEAD 不会执行 StreamingResponseBody：上游流必须立即关闭，不能挂在响应对象上等回收。
                closeQuietly(upstreamResponse);
                return responseBuilder(upstreamResponse, session).build();
            }
            HttpResponse<InputStream> openedUpstream = upstreamResponse;
            StreamingResponseBody body = outputStream -> {
                try (InputStream upstream = openedUpstream.body()) {
                    byte[] buffer = new byte[BUFFER_SIZE];
                    int bytesRead;
                    while ((bytesRead = upstream.read(buffer)) != -1) {
                        outputStream.write(buffer, 0, bytesRead);
                    }
                    outputStream.flush();
                } catch (AsyncRequestNotUsableException exception) {
                    log.debug("音乐播放客户端已断开: sessionId={}", session.sessionId());
                } catch (IOException exception) {
                    if (isClientDisconnect(exception)) {
                        log.debug("音乐播放流已中断: sessionId={}, message={}", session.sessionId(), exception.getMessage());
                    } else {
                        log.warn("音乐播放流输出失败: sessionId={}, message={}", session.sessionId(), exception.getMessage());
                    }
                } catch (RuntimeException exception) {
                    if (isClientDisconnect(exception)) {
                        log.debug("音乐播放流已中断: sessionId={}, message={}", session.sessionId(), exception.getMessage());
                    } else {
                        throw exception;
                    }
                }
            };
            return responseBuilder(upstreamResponse, session).body(body);
        } catch (BusinessException exception) {
            closeQuietly(upstreamResponse);
            log.warn("音乐播放流安全校验失败: sessionId={}, message={}", session.sessionId(), exception.getMessage());
            return ResponseEntity.badRequest().build();
        } catch (InterruptedException exception) {
            closeQuietly(upstreamResponse);
            Thread.currentThread().interrupt();
            return ResponseEntity.internalServerError().build();
        } catch (IOException | IllegalArgumentException exception) {
            closeQuietly(upstreamResponse);
            log.warn("音乐播放流输出失败: sessionId={}, message={}", session.sessionId(), exception.getMessage());
            return ResponseEntity.badRequest().build();
        }
    }

    /**
     * 本地曲库直接读取 File 模块内容并按 Range 输出。
     *
     * <p>不能用面向浏览器的下载地址做服务端回环：本地只读来源签发的是相对路径，
     * MinIO 使用 publicEndpoint，二者在容器内都请求不到。</p>
     */
    private ResponseEntity<StreamingResponseBody> streamLocalSession(
            MusicPlaybackSession session,
            String range,
            boolean headRequest
    ) {
        MusicTrack track = session.trackId() == null
                ? null
                : trackRepository.findById(session.trackId()).orElse(null);
        if (track == null || track.getFileNodeId() == null) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        UUID requesterUserId = session.ownerUserId();
        UUID fileNodeId = track.getFileNodeId();
        // 大小取自元数据：为探测大小先打开一次对象存储流、再为输出打开第二次，
        // 每次播放都会多一次 GetObject 往返与连接占用。
        Optional<FileDescriptor> descriptor = fileMetadataQueryService
                .findAllByIds(List.of(fileNodeId)).stream().findFirst();
        if (descriptor.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        long totalBytes = descriptor.get().sizeBytes();
        String contentType = guessContentType("", session.format());
        if (range == null || range.isBlank()) {
            FileContentStream content;
            try {
                content = filePlaybackContentService.openFileContent(requesterUserId, fileNodeId);
            } catch (BusinessException exception) {
                return localFailure(exception);
            }
            return localBody(
                    content,
                    content.inputStream(),
                    content.sizeBytes(),
                    contentType,
                    HttpStatus.OK,
                    null,
                    headRequest
            );
        }
        ByteRange parsed = parseRange(range, totalBytes);
        if (parsed == null) {
            return ResponseEntity.status(HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                    .header(HttpHeaders.CONTENT_RANGE, "bytes */" + totalBytes)
                    .build();
        }
        Optional<FileContentRange> slice = filePlaybackContentService.openFileRange(
                requesterUserId, fileNodeId, parsed.start(), parsed.length());
        if (slice.isEmpty()) {
            return ResponseEntity.status(HttpStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                    .header(HttpHeaders.CONTENT_RANGE, "bytes */" + totalBytes)
                    .build();
        }
        FileContentRange content = slice.get();
        return localBody(
                content,
                content.inputStream(),
                parsed.length(),
                contentType,
                HttpStatus.PARTIAL_CONTENT,
                "bytes " + parsed.start() + "-" + parsed.end() + "/" + content.totalBytes(),
                headRequest
        );
    }

    private ResponseEntity<StreamingResponseBody> localBody(
            AutoCloseable handle,
            InputStream input,
            long contentLength,
            String contentType,
            HttpStatus status,
            String contentRange,
            boolean headRequest
    ) {
        ResponseEntity.BodyBuilder builder = ResponseEntity.status(status)
                .header(HttpHeaders.CONTENT_TYPE, contentType)
                .header(HttpHeaders.ACCEPT_RANGES, "bytes")
                .header(HttpHeaders.CONTENT_LENGTH, Long.toString(contentLength))
                .header(HttpHeaders.CACHE_CONTROL, "no-store, no-cache, must-revalidate")
                .header(HttpHeaders.PRAGMA, "no-cache");
        if (contentRange != null) {
            builder.header(HttpHeaders.CONTENT_RANGE, contentRange);
        }
        if (headRequest) {
            closeLocalQuietly(handle);
            return builder.build();
        }
        StreamingResponseBody body = outputStream -> {
            try {
                byte[] buffer = new byte[BUFFER_SIZE];
                int bytesRead;
                while ((bytesRead = input.read(buffer)) != -1) {
                    outputStream.write(buffer, 0, bytesRead);
                }
                outputStream.flush();
            } catch (AsyncRequestNotUsableException exception) {
                log.debug("本地曲目客户端已断开: message={}", exception.getMessage());
            } catch (IOException exception) {
                if (isClientDisconnect(exception)) {
                    log.debug("本地曲目流已中断: message={}", exception.getMessage());
                } else {
                    log.warn("本地曲目流输出失败: message={}", exception.getMessage());
                }
            } finally {
                closeLocalQuietly(handle);
            }
        };
        return builder.body(body);
    }

    private void closeLocalQuietly(AutoCloseable handle) {
        try {
            handle.close();
        } catch (Exception exception) {
            log.debug("关闭本地曲目流失败: errorType={}", exception.getClass().getSimpleName());
        }
    }

    private ResponseEntity<StreamingResponseBody> localFailure(BusinessException exception) {
        HttpStatus status = ErrorCode.FILE_NOT_FOUND.equals(exception.errorCode())
                ? HttpStatus.NOT_FOUND
                : HttpStatus.FORBIDDEN;
        return ResponseEntity.status(status).build();
    }

    private ByteRange parseRange(String header, long totalBytes) {
        String value = header.trim();
        if (!value.regionMatches(true, 0, "bytes=", 0, 6) || totalBytes <= 0) {
            return null;
        }
        String spec = value.substring(6).trim();
        int dash = spec.indexOf('-');
        if (dash < 0) {
            return null;
        }
        String startPart = spec.substring(0, dash).trim();
        String endPart = spec.substring(dash + 1).trim();
        try {
            long start;
            long end;
            if (startPart.isEmpty()) {
                long suffix = Long.parseLong(endPart);
                if (suffix <= 0) {
                    return null;
                }
                start = Math.max(0, totalBytes - suffix);
                end = totalBytes - 1;
            } else {
                start = Long.parseLong(startPart);
                end = endPart.isEmpty() ? totalBytes - 1 : Long.parseLong(endPart);
            }
            if (start < 0 || start >= totalBytes || end < start) {
                return null;
            }
            return new ByteRange(start, Math.min(end, totalBytes - 1));
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private record ByteRange(long start, long end) {
        private long length() {
            return end - start + 1;
        }
    }

    private ResponseEntity.BodyBuilder responseBuilder(
            HttpResponse<InputStream> upstreamResponse,
            MusicPlaybackSession session
    ) {
        ResponseEntity.BodyBuilder builder = ResponseEntity.status(upstreamResponse.statusCode())
                .header("Content-Type", contentType(upstreamResponse, session))
                .header("Accept-Ranges", "bytes")
                .header("Cache-Control", "no-store, no-cache, must-revalidate")
                .header("Pragma", "no-cache");
        contentLength(upstreamResponse).ifPresent(value -> builder.header("Content-Length", value));
        upstreamResponse.headers().firstValue("Content-Range")
                .ifPresent(value -> builder.header("Content-Range", value));
        return builder;
    }

    private void closeQuietly(HttpResponse<InputStream> upstreamResponse) {
        if (upstreamResponse == null) {
            return;
        }
        try {
            upstreamResponse.body().close();
        } catch (IOException exception) {
            log.debug("关闭音乐上游流失败: errorType={}", exception.getClass().getSimpleName());
        }
    }

    private HttpResponse<InputStream> sendWithRedirects(
            MusicPlaybackSession session,
            String range
    ) throws IOException, InterruptedException {
        URI current = URI.create(session.sourceUrl());
        for (int index = 0; index <= MAX_REDIRECT_COUNT; index++) {
            validateSourceUri(session, current);
            HttpRequest request = requestBuilder(current, range).build();
            HttpResponse<InputStream> response = httpClient.send(request, HttpResponse.BodyHandlers.ofInputStream());
            if (!isRedirect(response.statusCode())) {
                return response;
            }
            String location = response.headers().firstValue("Location").orElse(null);
            response.body().close();
            if (location == null || location.isBlank()) {
                throw new BusinessException(ErrorCode.BAD_REQUEST, "上游重定向缺少 Location");
            }
            current = current.resolve(location);
        }
        throw new BusinessException(ErrorCode.BAD_REQUEST, "上游重定向次数过多");
    }

    private HttpRequest.Builder requestBuilder(URI uri, String range) {
        HttpRequest.Builder builder = HttpRequest.newBuilder(uri)
                .timeout(REQUEST_TIMEOUT)
                .header("Referer", resolveReferer(uri))
                .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                .GET();
        if (range != null && !range.isBlank()) {
            builder.header("Range", range);
        }
        return builder;
    }

    private void validateSourceUri(MusicPlaybackSession session, URI uri) {
        if (session.sourceType() == MusicPlaybackSourceType.ONLINE) {
            sourceUrlPolicy.requireAllowed(session.sourcePlatform(), uri);
        }
    }

    /**
     * 判断异常是否属于客户端断开或异步取消。
     *
     * <p>流式响应被中断时 JDK HttpClient 会把 {@link InterruptedException} 包成
     * {@link IOException}，Tomcat 在客户端断开时也会抛出连接类 IOException。
     * 这类中断不代表上游或系统故障，应静默结束而不是进入全局异常。</p>
     */
    private boolean isClientDisconnect(Throwable throwable) {
        Throwable current = throwable;
        while (current != null) {
            if (current instanceof InterruptedException
                    || current instanceof AsyncRequestNotUsableException) {
                return true;
            }
            String message = current.getMessage();
            if (message != null) {
                String lower = message.toLowerCase(Locale.ROOT);
                if (lower.contains("broken pipe")
                        || lower.contains("connection reset")
                        || lower.contains("connection aborted")
                        || lower.contains("client abort")) {
                    return true;
                }
            }
            current = current.getCause() == current ? null : current.getCause();
        }
        return false;
    }

    private boolean isRedirect(int statusCode) {
        return statusCode == HttpStatus.MOVED_PERMANENTLY.value()
                || statusCode == HttpStatus.FOUND.value()
                || statusCode == HttpStatus.SEE_OTHER.value()
                || statusCode == HttpStatus.TEMPORARY_REDIRECT.value()
                || statusCode == HttpStatus.PERMANENT_REDIRECT.value();
    }

    private String contentType(HttpResponse<InputStream> response, MusicPlaybackSession session) {
        return response.headers().firstValue("Content-Type")
                .orElseGet(() -> guessContentType(session.sourceUrl(), session.format()));
    }

    private Optional<String> contentLength(HttpResponse<InputStream> response) {
        return response.headers().firstValue("Content-Length")
                .filter(value -> value.chars().allMatch(Character::isDigit));
    }

    private String resolveReferer(URI uri) {
        String lower = uri.toString().toLowerCase(Locale.ROOT);
        if (lower.contains("music.163.com") || lower.contains("music.126.net")) {
            return "https://music.163.com/";
        }
        String scheme = uri.getScheme() == null ? "https" : uri.getScheme();
        String host = uri.getHost() == null ? "" : uri.getHost();
        return scheme + "://" + host + "/";
    }

    private String guessContentType(String url, String format) {
        String lower = ((format == null ? "" : format) + " " + url).toLowerCase(Locale.ROOT);
        if (lower.contains("flac")) {
            return "audio/flac";
        }
        if (lower.contains("mp3") || lower.contains("mpeg")) {
            return "audio/mpeg";
        }
        if (lower.contains("m4a") || lower.contains("mp4")) {
            return "audio/mp4";
        }
        if (lower.contains("ogg")) {
            return "audio/ogg";
        }
        if (lower.contains("wav")) {
            return "audio/wav";
        }
        if (lower.contains("aac")) {
            return "audio/aac";
        }
        return "application/octet-stream";
    }
}
