package com.omninest.modules.user.service;

import com.omninest.common.api.PageResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.user.domain.AuditLog;
import com.omninest.modules.user.domain.AuthActiveSession;
import com.omninest.modules.user.domain.AuthLoginAudit;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.dto.AdminOperationDescription;
import com.omninest.modules.user.dto.AdminOperationsDto;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import com.omninest.modules.user.repository.AuditLogAdminRepository;
import com.omninest.modules.user.repository.AuthLoginAuditRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.repository.TaskRecordAdminRepository;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 管理端大数据列表分页查询服务。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class AdminOperationsPagingService {
    private static final int DEFAULT_PAGE_SIZE = 25;
    private static final int MAX_PAGE_SIZE = 100;
    private static final int MAX_PAGE_INDEX = 1_000_000;
    private static final int MAX_FILTER_LENGTH = 100;
    private static final int MAX_SEARCH_LENGTH = 200;

    private final TaskRecordAdminRepository taskRecordRepository;
    private final AuditLogAdminRepository auditLogRepository;
    private final ActiveSessionRepository activeSessionRepository;
    private final AuthLoginAuditRepository loginAuditRepository;
    private final AuthUserRepository authUserRepository;

    /**
     * 分页查询后台任务。
     *
     * @param page 页码，从零开始
     * @param size 每页数量
     * @param status 任务状态
     * @param taskType 任务类型
     * @param query 搜索词
     * @return 任务分页结果
     */
    @Transactional(readOnly = true)
    public PageResponse<AdminOperationsDto.TaskRecordItem> taskPage(
            int page,
            int size,
            String status,
            String taskType,
            String query,
            String sort,
            String dir
    ) {
        int pageIndex = normalizePage(page);
        int pageSize = normalizePageSize(size);
        String normalizedStatus = normalizeFilter(status, true);
        String normalizedTaskType = normalizeFilter(taskType, true);
        String searchPattern = searchPattern(query);
        String sortColumn = taskSortColumn(sort);
        boolean ascending = "asc".equalsIgnoreCase(dir);
        TaskRecordAdminRepository.TaskPage result = taskRecordRepository.findPage(
                pageIndex, pageSize, normalizedStatus, normalizedTaskType, searchPattern,
                sortColumn, ascending
        );
        int totalPages = totalPages(result.totalElements(), pageSize);
        if (result.items().isEmpty() && pageIndex > 0 && totalPages > 0) {
            pageIndex = totalPages - 1;
            result = taskRecordRepository.findPage(
                    pageIndex, pageSize, normalizedStatus, normalizedTaskType, searchPattern,
                    sortColumn, ascending
            );
        }
        return PageResponse.of(toTaskItems(result.items()), pageIndex, pageSize, result.totalElements());
    }

    /**
     * 分页查询操作审计日志。
     *
     * @param page 页码，从零开始
     * @param size 每页数量
     * @param action 操作类型
     * @param query 搜索词
     * @return 操作审计分页结果
     */
    @Transactional(readOnly = true)
    public PageResponse<AdminOperationsDto.AuditLogItem> logPage(
            int page,
            int size,
            String action,
            String query,
            String sort,
            String dir
    ) {
        int pageIndex = normalizePage(page);
        int pageSize = normalizePageSize(size);
        String normalizedAction = normalizeFilter(action, true);
        String searchPattern = searchPattern(query);
        Sort sortSpec = adminSort(sort, dir, Map.of("createdat", "createdAt", "action", "action"), "createdat");
        Page<AuditLog> result = auditLogRepository.searchAdminLogs(
                normalizedAction, searchPattern, PageRequest.of(pageIndex, pageSize, sortSpec)
        );
        if (result.isEmpty() && pageIndex > 0 && result.getTotalPages() > 0) {
            pageIndex = result.getTotalPages() - 1;
            result = auditLogRepository.searchAdminLogs(
                    normalizedAction, searchPattern, PageRequest.of(pageIndex, pageSize, sortSpec)
            );
        }
        return PageResponse.of(toAuditItems(result.getContent()), pageIndex, pageSize, result.getTotalElements());
    }

    /**
     * 分页查询系统会话。
     *
     * @param page 页码，从零开始
     * @param size 每页数量
     * @param status 会话状态
     * @param platform 客户端平台
     * @param query 搜索词
     * @param sort 排序字段，白名单外的取值回退为最后活跃时间
     * @return 会话分页结果
     */
    @Transactional(readOnly = true)
    public PageResponse<AdminOperationsDto.SessionItem> sessionPage(
            int page,
            int size,
            String status,
            String platform,
            String query,
            String sort,
            String dir
    ) {
        int pageIndex = normalizePage(page);
        int pageSize = normalizePageSize(size);
        String normalizedStatus = normalizeFilter(status, true);
        String normalizedPlatform = normalizeFilter(platform, false);
        String searchPattern = searchPattern(query);
        Instant now = Instant.now();
        Sort sortSpec = adminSort(sort, dir, Map.of(
                "lastactiveat", "lastActiveAt",
                "issuedat", "issuedAt",
                "expiresat", "expiresAt",
                "username", "user.username"
        ), "lastactiveat");
        Page<AuthActiveSession> result = activeSessionRepository.searchAdminSessions(
                normalizedStatus,
                normalizedPlatform,
                searchPattern,
                now,
                PageRequest.of(pageIndex, pageSize, sortSpec)
        );
        if (result.isEmpty() && pageIndex > 0 && result.getTotalPages() > 0) {
            pageIndex = result.getTotalPages() - 1;
            result = activeSessionRepository.searchAdminSessions(
                    normalizedStatus,
                    normalizedPlatform,
                    searchPattern,
                    now,
                    PageRequest.of(pageIndex, pageSize, sortSpec)
            );
        }
        return PageResponse.of(toSessionItems(result.getContent()), pageIndex, pageSize, result.getTotalElements());
    }

    /**
     * 分页查询登录审计记录。
     *
     * @param page 页码，从零开始
     * @param size 每页数量
     * @param result 登录结果
     * @param platform 客户端平台
     * @param query 搜索词
     * @return 登录审计分页结果
     */
    @Transactional(readOnly = true)
    public PageResponse<AdminOperationsDto.LoginAuditItem> loginAuditPage(
            int page,
            int size,
            String result,
            String platform,
            String query,
            String sort,
            String dir
    ) {
        int pageIndex = normalizePage(page);
        int pageSize = normalizePageSize(size);
        String normalizedResult = normalizeFilter(result, true);
        String normalizedPlatform = normalizeFilter(platform, false);
        String searchPattern = searchPattern(query);
        Sort sortSpec = adminSort(sort, dir, Map.of("createdat", "createdAt", "username", "username"), "createdat");
        Page<AuthLoginAudit> auditPage = loginAuditRepository.searchAdminAudits(
                normalizedResult, normalizedPlatform, searchPattern, PageRequest.of(pageIndex, pageSize, sortSpec)
        );
        if (auditPage.isEmpty() && pageIndex > 0 && auditPage.getTotalPages() > 0) {
            pageIndex = auditPage.getTotalPages() - 1;
            auditPage = loginAuditRepository.searchAdminAudits(
                    normalizedResult, normalizedPlatform, searchPattern, PageRequest.of(pageIndex, pageSize, sortSpec)
            );
        }
        return PageResponse.of(
                toLoginAuditItems(auditPage.getContent()),
                pageIndex,
                pageSize,
                auditPage.getTotalElements()
        );
    }

    private List<AdminOperationsDto.TaskRecordItem> toTaskItems(List<Object[]> rows) {
        return rows.stream().map(row -> new AdminOperationsDto.TaskRecordItem(
                toUuid(row[0]), toText(row[1]), AdminOperationDescription.task(toText(row[1]), toText(row[4])),
                toText(row[2]), toInt(row[3]), toText(row[4]), toText(row[5]), toInt(row[6]),
                toInstant(row[7]), toInstant(row[8]),
                toUuidOrNull(row[9]), toText(row[10])
        )).toList();
    }

    private List<AdminOperationsDto.AuditLogItem> toAuditItems(List<AuditLog> logs) {
        return logs.stream().map(audit -> new AdminOperationsDto.AuditLogItem(
                audit.getId(), audit.getActorUserId(), audit.getAction(),
                AdminOperationDescription.audit(audit.getAction(), audit.getResourceType()),
                audit.getResourceType(), audit.getResourceId(), audit.getIpAddress(), audit.getCreatedAt()
        )).toList();
    }

    private List<AdminOperationsDto.SessionItem> toSessionItems(List<AuthActiveSession> sessions) {
        Set<UUID> userIds = sessions.stream()
                .map(AuthActiveSession::getUserId)
                .collect(Collectors.toSet());
        Map<UUID, String> usernameMap = userIds.isEmpty()
                ? Map.of()
                : authUserRepository.findAllById(userIds).stream()
                .collect(Collectors.toMap(
                        AuthUser::getId,
                        user -> user.getUsername() == null ? "" : user.getUsername()
                ));
        return sessions.stream().map(session -> new AdminOperationsDto.SessionItem(
                session.getId(), session.getUserId(), usernameMap.getOrDefault(session.getUserId(), ""),
                session.getClientPlatform(), session.getDeviceId(), session.getDeviceName(), session.getIpAddress(),
                session.getIssuedAt(), session.getExpiresAt(), session.getLastActiveAt(),
                session.getRevokedAt(), session.getRevokeReason()
        )).toList();
    }

    private List<AdminOperationsDto.LoginAuditItem> toLoginAuditItems(List<AuthLoginAudit> audits) {
        return audits.stream().map(audit -> new AdminOperationsDto.LoginAuditItem(
                audit.getId(), audit.getUserId(), audit.getUsername(), audit.getLoginResult(),
                audit.getClientPlatform(), audit.getIpAddress(), audit.getUserAgent(),
                audit.getFailureReason(), audit.getCreatedAt()
        )).toList();
    }

    /**
     * 构建管理端分页排序：字段仅允许白名单，方向由 dir 决定（默认倒序），并追加 id 倒序兜底。
     */
    private Sort adminSort(String sort, String dir, Map<String, String> whitelist, String defaultField) {
        String requested = sort == null ? "" : sort.toLowerCase(Locale.ROOT);
        String property = whitelist.getOrDefault(requested, whitelist.get(defaultField));
        Sort.Direction direction = "asc".equalsIgnoreCase(dir) ? Sort.Direction.ASC : Sort.Direction.DESC;
        return Sort.by(direction, property).and(Sort.by(Sort.Direction.DESC, "id"));
    }

    /**
     * 任务排序白名单：仅允许映射到固定 SQL 列的字段，其余回退为更新时间。
     */
    private String taskSortColumn(String sort) {
        return switch (sort == null ? "" : sort.toLowerCase(Locale.ROOT)) {
            case "progress" -> "progress";
            case "tasktype" -> "task_type";
            case "status" -> "status";
            case "createdat" -> "created_at";
            default -> "updated_at";
        };
    }

    private int normalizePage(int page) {
        return Math.min(Math.max(0, page), MAX_PAGE_INDEX);
    }

    private int normalizePageSize(int size) {
        int requested = size <= 0 ? DEFAULT_PAGE_SIZE : size;
        return Math.min(requested, MAX_PAGE_SIZE);
    }

    private String normalizeFilter(String value, boolean uppercase) {
        if (value == null || value.isBlank() || "ALL".equalsIgnoreCase(value.trim())) {
            return "";
        }
        String normalized = value.trim();
        if (normalized.length() > MAX_FILTER_LENGTH) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "筛选条件长度不能超过 100 个字符");
        }
        return uppercase ? normalized.toUpperCase(Locale.ROOT) : normalized.toLowerCase(Locale.ROOT);
    }

    private String searchPattern(String query) {
        if (query == null || query.isBlank()) {
            return "";
        }
        String normalized = query.trim().toLowerCase(Locale.ROOT);
        if (normalized.length() > MAX_SEARCH_LENGTH) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "搜索条件长度不能超过 200 个字符");
        }
        return "%" + normalized + "%";
    }

    private int totalPages(long totalElements, int pageSize) {
        return totalElements == 0 ? 0 : (int) Math.ceil((double) totalElements / pageSize);
    }

    private UUID toUuid(Object value) {
        if (value instanceof UUID uuid) {
            return uuid;
        }
        return UUID.fromString(value.toString());
    }

    /**
     * 系统任务的归属用户可以为空，单行缺失不得让整页转换失败。
     */
    private UUID toUuidOrNull(Object value) {
        if (value == null) {
            return null;
        }
        return toUuid(value);
    }

    private String toText(Object value) {
        return value == null ? null : value.toString();
    }

    private int toInt(Object value) {
        if (value instanceof Number number) {
            return number.intValue();
        }
        return Integer.parseInt(value.toString());
    }

    private Instant toInstant(Object value) {
        if (value instanceof Instant instant) {
            return instant;
        }
        if (value instanceof Timestamp timestamp) {
            return timestamp.toInstant();
        }
        return Instant.parse(value.toString());
    }
}
