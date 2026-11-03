package com.omninest.app.architecture;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 跨模块架构不变量守护测试（Architecture Ratchet）。
 *
 * <p>这里钉住的都是“本轮修好、下一轮又被同类写法带回来”的缺陷模式：
 * 无事务上下文注册事务同步器、长连接只校验会话撤销不校验令牌陈旧、自建 HttpClient
 * 跟随重定向、非唯一列上返回单值、活动目录改名污染回收站路径、长任务缺少心跳、
 * 批量入口逐条鉴权。每一条都对应过一次真实缺陷，测试只断言最小可判定特征，
 * 不复制业务实现。</p>
 *
 * @author OmniNest
 */
class ArchitectureInvariantsTest {

    private static final Pattern HTTP_CLIENT_BUILDER =
            Pattern.compile("HttpClient\\.newBuilder\\(\\)[\\s\\S]{0,320}?\\.build\\(\\)");

    private static final Pattern SINGLE_RESULT_FINDER =
            Pattern.compile("Optional<[A-Za-z0-9_]+>\\s+(find[A-Za-z0-9_]*)\\(");

    /**
     * 单值查询里必须带确定性排序的身份列片段。 */
    private static final List<String> NON_UNIQUE_IDENTITY_SEGMENTS = List.of(
            "AndTitle", "AndName", "AndTmdbId", "findByTmdbId");

    /**
     * 由唯一索引兜底的单值查询：活动节点的同父（或同根）同名行受活动路径唯一索引约束
     * 最多一行，不需要 findFirst + OrderBy。例外必须按闸门输出的完整坐标登记，禁止空手放行。
     */
    private static final List<String> UNIQUE_INDEX_BACKED_FINDERS = List.of(
            "omninest-file/src/main/java/com/omninest/modules/file/repository/FileNodeRepository.java"
                    + "#findFirstBySpaceTypeAndParentIdAndNameAndDeletedFalse",
            "omninest-file/src/main/java/com/omninest/modules/file/repository/FileNodeRepository.java"
                    + "#findFirstBySpaceTypeAndParentIdIsNullAndNameAndDeletedFalse",
            "omninest-file/src/main/java/com/omninest/modules/file/repository/FileNodeRepository.java"
                    + "#findFirstByOwnerUserIdAndSpaceTypeAndParentIdAndNameAndDeletedFalse",
            "omninest-file/src/main/java/com/omninest/modules/file/repository/FileNodeRepository.java"
                    + "#findFirstByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndNameAndDeletedFalse");

    @Test
    @DisplayName("registerSynchronization 调用必须同时判断 isSynchronizationActive")
    void registerSynchronizationMustCheckActive() throws IOException {
        List<String> violations = new ArrayList<>();
        for (Path file : mainJavaFiles()) {
            String content = Files.readString(file);
            if (content.contains("registerSynchronization")
                    && !content.contains("isSynchronizationActive()")) {
                violations.add(relative(file));
            }
        }
        assertThat(violations)
                .as("无事务上下文注册事务同步器会抛 IllegalStateException")
                .isEmpty();
    }

    @Test
    @DisplayName("STOMP 认证与会话巡检必须与 HTTP 对称校验令牌陈旧")
    void realtimeAuthenticationMustCheckTokenStale() throws IOException {
        for (Path file : mainJavaFiles()) {
            String name = file.getFileName().toString();
            if ("RealtimeStompAuthenticationInterceptor.java".equals(name)
                    || "RealtimeWebSocketSessionRegistry.java".equals(name)) {
                String content = Files.readString(file);
                assertThat(content)
                        .as(name + " 必须同时校验 isRevoked 与 isTokenStale")
                        .contains("isRevoked(")
                        .contains("isTokenStale(");
            }
        }
    }

    @Test
    @DisplayName("自建 HttpClient 必须显式禁用自动重定向")
    void httpClientBuildersMustDisableRedirects() throws IOException {
        List<String> violations = new ArrayList<>();
        for (Path file : mainJavaFiles()) {
            String content = Files.readString(file);
            Matcher matcher = HTTP_CLIENT_BUILDER.matcher(content);
            while (matcher.find()) {
                if (!matcher.group().contains("followRedirects(HttpClient.Redirect.NEVER)")) {
                    violations.add(relative(file));
                }
            }
        }
        assertThat(violations)
                .as("跟随 302 会绕过首次 SSRF 校验，把请求带到内网或云元数据地址")
                .isEmpty();
    }

    @Test
    @DisplayName("非唯一身份列上的单值查询必须 findFirst + OrderBy")
    void singleResultFindersOnNonUniqueColumnsMustBeDeterministic() throws IOException {
        List<String> violations = new ArrayList<>();
        for (Path file : mainJavaFiles()) {
            String fileName = file.getFileName().toString();
            if (!fileName.endsWith("Repository.java")) {
                continue;
            }
            String content = Files.readString(file);
            Matcher matcher = SINGLE_RESULT_FINDER.matcher(content);
            while (matcher.find()) {
                String method = matcher.group(1);
                boolean targetsIdentityColumn = NON_UNIQUE_IDENTITY_SEGMENTS.stream()
                        .anyMatch(method::contains);
                if (!targetsIdentityColumn) {
                    continue;
                }
                boolean deterministic = method.startsWith("findFirst") && method.contains("OrderBy");
                String coordinate = relative(file) + "#" + method;
                if (!deterministic && !UNIQUE_INDEX_BACKED_FINDERS.contains(coordinate)) {
                    violations.add(coordinate);
                }
            }
        }
        assertThat(violations)
                .as("同名/同 TMDB ID 允许存在多行，单值查询必须带确定性排序，否则抛 500")
                .isEmpty();
    }

    @Test
    @DisplayName("活动目录改名只能重写活动节点，回收站节点由恢复流程按 parent_id 重算")
    void pathRewriteMustOnlyTouchActiveNodes() throws IOException {
        List<String> violations = new ArrayList<>();
        for (Path file : mainJavaFiles()) {
            String name = file.getFileName().toString();
            if (!"FilePathRewriter.java".equals(name) && !"SharedSpaceService.java".equals(name)) {
                continue;
            }
            String content = Files.readString(file);
            if (content.contains("findSubtreeBySpaceTypeAfterId(")
                    || content.contains("findPersonalSubtreeAfterId(")) {
                violations.add(relative(file));
            }
        }
        assertThat(violations)
                .as("含回收站节点的子树查询会把已删节点路径改成活动目录的新前缀")
                .isEmpty();
    }

    /**
     * 恢复调度器可能重投的任务类型 → 该类型的存活信号归属。
     *
     * <p>判据来自 {@code findStaleRunningTasks}：{@code heartbeatAt is null or heartbeatAt < cutoff}。
     * 因此凡是进入 {@code RECOVERED_TASK_TYPES} 的类型，执行体必须在运行期间刷新心跳或进度，
     * 否则跑过 stale 阈值就会被判定僵尸并重投，与仍在执行的原线程并发改同一批业务对象。
     * DEF-M04 只报了 {@code LOCAL_VIDEO_LIBRARY_APPLY} 一处，但同一形状的暴露面是整个类型表，
     * 所以这里钉的是「每个类型都要声明归属」，而不是某一次修复。</p>
     */
    private static final Map<String, String> TASK_LIVENESS_DECLARATIONS = Map.ofEntries(
            Map.entry("PHOTO_SCAN", "PhotoAdminService 持有 TaskHeartbeatRunner 租约"),
            Map.entry("PHOTO_THUMBNAILS", "PhotoBatchService 逐项 updateProgress，进度写入同时播心跳"),
            Map.entry("PHOTO_BATCH", "PhotoBatchService 逐项 updateProgress"),
            Map.entry("PHOTO_MOTION", "经 FilePostProcessingTaskTracker 生命周期领取，租约由跟踪器持有"),
            Map.entry("PHOTO_MOTION_RESCAN", "经 FilePostProcessingTaskTracker 生命周期领取"),
            Map.entry("EXTERNAL_IMPORT", "ExternalImportExecutionService 分片进度刷新"),
            Map.entry("MEDIA_SCRAPE", "MovieScrapeExecutionService 领取后持有租约直至终态"),
            Map.entry("VIDEO_TRANSCODE", "TranscodeExecutionService 持有 TaskHeartbeatRunner 租约"),
            Map.entry("WEB_OPTIMIZE", "经 FilePostProcessingTaskTracker 生命周期领取"),
            Map.entry("AUDIO_EXTRACT", "经 FilePostProcessingTaskTracker 生命周期领取"),
            Map.entry("FILE_INDEX", "经 FilePostProcessingTaskTracker 生命周期领取"),
            Map.entry("THUMBNAIL", "经 FilePostProcessingTaskTracker 生命周期领取"),
            Map.entry("TEXT_EXTRACTION", "经 FilePostProcessingTaskTracker 生命周期领取"),
            Map.entry("SEARCH_INDEX_REBUILD", "SearchIndexRebuildService 分批 updateProgress"),
            Map.entry("LOCAL_VIDEO_LIBRARY_DISCOVERY", "发现批次刷新进度"),
            Map.entry("LOCAL_VIDEO_LIBRARY_APPLY", "MediaLibraryApplyExecutor 全程持有租约"),
            // 邮件通知是一次 SMTP 提交：它不持任何业务对象的写权限，被重投最多产生
            // 第二封同样的邮件。这里记录为已评审的可重复，而不是漏掉存活信号。
            Map.entry("NOTIFICATION_EMAIL", "无业务写侧的可重复投递；重投只会补发一封通知"));

    @Test
    @DisplayName("恢复调度器覆盖的每个任务类型都必须声明存活信号归属")
    void everyRecoveredTaskTypeDeclaresLivenessOwner() throws IOException {
        String scheduler = Files.readString(backendRoot().resolve(
                "omninest-worker/src/main/java/com/omninest/worker/task/GenericTaskRecoveryScheduler.java"));
        int start = scheduler.indexOf("RECOVERED_TASK_TYPES = List.of(");
        assertThat(start).as("恢复调度器的类型表必须存在").isGreaterThanOrEqualTo(0);
        int end = scheduler.indexOf(");", start);
        assertThat(end).as("类型表必须能定界，否则闸门失去判定基线").isGreaterThan(start);
        List<String> types = new ArrayList<>();
        Matcher literal = Pattern.compile("\"([A-Z_]+)\"").matcher(scheduler.substring(start, end));
        while (literal.find()) {
            types.add(literal.group(1));
        }
        assertThat(types)
                .as("新增可恢复任务类型必须先声明存活归属，否则等于放任僵尸重投")
                .allMatch(TASK_LIVENESS_DECLARATIONS::containsKey);
        assertThat(TASK_LIVENESS_DECLARATIONS.keySet())
                .as("登记表里不允许留下已从调度器移除的类型")
                .containsExactlyInAnyOrderElementsOf(types);
    }

    @Test
    @DisplayName("按咽喉点持有心跳租约的执行体不得退化成裸执行")
    void livenessOwnersMustRefreshHeartbeat() throws IOException {
        List<String> owners = List.of(
                "omninest-worker/src/main/java/com/omninest/worker/file/FilePostProcessingTaskTracker.java",
                "omninest-media/src/main/java/com/omninest/modules/video/service/MovieScrapeExecutionService.java",
                "omninest-media/src/main/java/com/omninest/modules/video/service/MediaLibraryApplyExecutor.java");
        List<String> violations = new ArrayList<>();
        for (String owner : owners) {
            String content = Files.readString(backendRoot().resolve(owner));
            if (!content.contains("taskHeartbeatRunner.start(")) {
                violations.add(owner);
            }
        }
        assertThat(violations)
                .as("这些执行体是可恢复任务的心跳咽喉点，失去租约即失去僵尸判定")
                .isEmpty();
    }

    @Test
    @DisplayName("批量配额入口必须使用批量查询与批量更新")
    void batchQuotaMustStayBatched() throws IOException {
        Path quotaService = backendRoot()
                .resolve("omninest-system/src/main/java/com/omninest/modules/quota/service/"
                        + "StorageQuotaService.java");
        String content = Files.readString(quotaService);
        int start = content.indexOf("public int batchUpdateQuota(");
        assertThat(start).as("batchUpdateQuota 必须存在").isGreaterThanOrEqualTo(0);
        int end = content.indexOf("private Map<String, Object> quotaAuditPayload", start);
        String method = end > start ? content.substring(start, end) : content.substring(start);
        assertThat(method)
                .as("批量入口必须一次取回摘要并为目标用户批量写入")
                .contains("findSummariesByIds")
                .contains("updateQuotaBatch");
        assertThat(method)
                .as("批量入口不得逐条做权限校验，否则全选本页必然 403")
                .doesNotContain("requireQuotaMutationAuthority");
    }

    @Test
    @DisplayName("配额对账修正后必须淘汰用户资料缓存")
    void quotaReconcileMustEvictProfileCache() throws IOException {
        Path quotaService = backendRoot()
                .resolve("omninest-system/src/main/java/com/omninest/modules/quota/service/"
                        + "StorageQuotaService.java");
        String content = Files.readString(quotaService);
        int start = content.indexOf("public int recalculateAllUsages(");
        assertThat(start).isGreaterThanOrEqualTo(0);
        int end = content.indexOf("public long getDefaultQuotaBytes", start);
        String method = end > start ? content.substring(start, end) : content.substring(start);
        assertThat(method)
                .as("对账改了 used_bytes 却不淘汰 Redis 资料缓存，前端会继续显示旧用量")
                .contains("evictProfileCacheAfterCommit");
    }

    private static Path backendRoot() {
        Path current = Path.of("").toAbsolutePath().normalize();
        for (int depth = 0; depth < 5 && current != null; depth++) {
            if (Files.isDirectory(current.resolve("omninest-common"))
                    && Files.isRegularFile(current.resolve("pom.xml"))) {
                return current;
            }
            current = current.getParent();
        }
        throw new IllegalStateException("无法定位 backend 根目录");
    }

    private static List<Path> mainJavaFiles() throws IOException {
        Path root = backendRoot();
        try (Stream<Path> walk = Files.walk(root)) {
            return walk.filter(Files::isRegularFile)
                    .filter(path -> path.toString().endsWith(".java"))
                    .filter(path -> path.toString().replace('\\', '/').contains("/src/main/java/"))
                    .toList();
        }
    }

    private static String relative(Path file) {
        return backendRoot().relativize(file).toString().replace('\\', '/');
    }
}
