package com.omninest.modules.music.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Locale;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
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
     * @return 音频流响应
     */
    public ResponseEntity<StreamingResponseBody> stream(String sessionId, String token, String range) {
        return sessionService.resolve(sessionId, token)
                .map(session -> streamResolvedSession(session, range))
                .orElseGet(() -> ResponseEntity.status(HttpStatus.UNAUTHORIZED).build());
    }

    private ResponseEntity<StreamingResponseBody> streamResolvedSession(
            MusicPlaybackSession session,
            String range
    ) {
        try {
            HttpResponse<InputStream> upstreamResponse = sendWithRedirects(session, range);
            int statusCode = upstreamResponse.statusCode();
            StreamingResponseBody body = outputStream -> {
                try (InputStream upstream = upstreamResponse.body()) {
                    byte[] buffer = new byte[BUFFER_SIZE];
                    int bytesRead;
                    while ((bytesRead = upstream.read(buffer)) != -1) {
                        outputStream.write(buffer, 0, bytesRead);
                    }
                    outputStream.flush();
                } catch (AsyncRequestNotUsableException exception) {
                    log.debug("音乐播放客户端已断开: sessionId={}", session.sessionId());
                }
            };
            ResponseEntity.BodyBuilder builder = ResponseEntity.status(statusCode)
                    .header("Content-Type", contentType(upstreamResponse, session))
                    .header("Accept-Ranges", "bytes")
                    .header("Cache-Control", "no-store, no-cache, must-revalidate")
                    .header("Pragma", "no-cache");
            contentLength(upstreamResponse).ifPresent(value -> builder.header("Content-Length", value));
            upstreamResponse.headers().firstValue("Content-Range")
                    .ifPresent(value -> builder.header("Content-Range", value));
            return builder.body(body);
        } catch (BusinessException exception) {
            log.warn("音乐播放流安全校验失败: sessionId={}, message={}", session.sessionId(), exception.getMessage());
            return ResponseEntity.badRequest().build();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return ResponseEntity.internalServerError().build();
        } catch (IOException | IllegalArgumentException exception) {
            log.warn("音乐播放流输出失败: sessionId={}, message={}", session.sessionId(), exception.getMessage());
            return ResponseEntity.badRequest().build();
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
