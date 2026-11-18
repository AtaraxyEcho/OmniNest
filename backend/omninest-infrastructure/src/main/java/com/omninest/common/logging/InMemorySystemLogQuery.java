package com.omninest.common.logging;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.LoggerContext;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.AppenderBase;
import com.omninest.common.logging.SystemLogEntry;
import com.omninest.common.logging.SystemLogPage;
import com.omninest.common.logging.SystemLogQuery;
import jakarta.annotation.PreDestroy;
import java.time.Instant;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeSet;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Pattern;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * 保存当前服务进程最近的日志，供受权限保护的运维查询使用。
 */
@Component
public class InMemorySystemLogQuery implements SystemLogQuery {
    private static final int CAPACITY = 10_000;
    private static final int MAX_MESSAGE_LENGTH = 4_000;
    private static final int MAX_PAGE_SIZE = 100;
    private static final String APPENDER_NAME = "OMNINEST_ADMIN_LOG_BUFFER";
    private static final Pattern SECRET_FIELD = Pattern.compile(
            "(?i)(password|secret(?:key)?|token|authorization|access[_-]?key|api[_-]?key|credential)"
                    + "(\\s*[:=]\\s*)(\"[^\"]*\"|'[^']*'|[^\\s,;]+)"
    );
    private static final Pattern BEARER_TOKEN = Pattern.compile(
            "(?i)Bearer\\s+[A-Za-z0-9._~+/-]+=*"
    );

    private final Object lock = new Object();
    private final Deque<SystemLogEntry> entries = new ArrayDeque<>(CAPACITY);
    private final AtomicLong sequence = new AtomicLong();
    private final AppenderBase<ILoggingEvent> appender = new AppenderBase<>() {
        @Override
        protected void append(ILoggingEvent event) {
            capture(event);
        }
    };
    private Logger rootLogger;

    /**
     * Spring Boot 完成日志初始化后再挂接，避免替换既有控制台和文件输出。
     */
    @EventListener(ApplicationReadyEvent.class)
    public synchronized void attach() {
        LoggerContext context = (LoggerContext) LoggerFactory.getILoggerFactory();
        rootLogger = context.getLogger(Logger.ROOT_LOGGER_NAME);
        if (rootLogger.getAppender(APPENDER_NAME) != null) {
            return;
        }
        appender.setContext(context);
        appender.setName(APPENDER_NAME);
        appender.start();
        rootLogger.addAppender(appender);
    }

    @PreDestroy
    public synchronized void detach() {
        if (rootLogger != null) {
            rootLogger.detachAppender(APPENDER_NAME);
        }
        appender.stop();
    }

    @Override
    public SystemLogPage search(String query, String level, String source, int page, int size) {
        int safePage = Math.max(0, page);
        int safeSize = Math.clamp(size, 1, MAX_PAGE_SIZE);
        String normalizedQuery = normalize(query);
        String normalizedLevel = normalize(level).toUpperCase(Locale.ROOT);
        String normalizedSource = normalize(source);
        List<SystemLogEntry> matches = new ArrayList<>();
        Map<String, Long> levelCounts = new LinkedHashMap<>();
        levelCounts.put("ERROR", 0L);
        levelCounts.put("WARN", 0L);
        levelCounts.put("INFO", 0L);
        levelCounts.put("DEBUG", 0L);
        TreeSet<String> sources = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
        synchronized (lock) {
            Iterator<SystemLogEntry> iterator = entries.descendingIterator();
            while (iterator.hasNext()) {
                SystemLogEntry entry = iterator.next();
                levelCounts.computeIfPresent(entry.level(), (key, count) -> count + 1);
                if (!entry.source().isBlank()) {
                    sources.add(entry.source());
                }
                if (matches(entry, normalizedQuery, normalizedLevel, normalizedSource)) {
                    matches.add(entry);
                }
            }
        }
        long offset = (long) safePage * safeSize;
        int start = offset >= matches.size() ? matches.size() : (int) offset;
        int end = Math.min(matches.size(), start + safeSize);
        return new SystemLogPage(
                matches.subList(start, end), safePage, safeSize, matches.size(),
                levelCounts, List.copyOf(sources));
    }

    private void capture(ILoggingEvent event) {
        String message = redact(event.getFormattedMessage());
        String source = event.getLoggerName() == null ? "" : event.getLoggerName();
        SystemLogEntry entry = new SystemLogEntry(
                sequence.incrementAndGet(),
                Instant.ofEpochMilli(event.getTimeStamp()),
                event.getLevel().toString(),
                source,
                message
        );
        synchronized (lock) {
            if (entries.size() == CAPACITY) {
                entries.removeFirst();
            }
            entries.addLast(entry);
        }
    }

    private boolean matches(SystemLogEntry entry, String query, String level, String source) {
        if (!level.isEmpty() && !entry.level().equalsIgnoreCase(level)) {
            return false;
        }
        String entrySource = entry.source().toLowerCase(Locale.ROOT);
        if (!source.isEmpty() && !entrySource.contains(source)) {
            return false;
        }
        if (query.isEmpty()) {
            return true;
        }
        return entry.message().toLowerCase(Locale.ROOT).contains(query)
                || entrySource.contains(query);
    }

    private String redact(String message) {
        if (message == null || message.isBlank()) {
            return "";
        }
        String safe = SECRET_FIELD.matcher(message).replaceAll("$1$2[REDACTED]");
        safe = BEARER_TOKEN.matcher(safe).replaceAll("Bearer [REDACTED]");
        if (safe.length() > MAX_MESSAGE_LENGTH) {
            safe = safe.substring(0, MAX_MESSAGE_LENGTH) + "…";
        }
        return safe;
    }

    private String normalize(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
    }
}
