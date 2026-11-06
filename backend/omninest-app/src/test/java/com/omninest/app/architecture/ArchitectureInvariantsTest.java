package com.omninest.app.architecture;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.HashMap;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
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

    /** 跨模块仓储注入：模块名 + repository 包下的任意类型。 */
    private static final Pattern CROSS_MODULE_REPOSITORY_IMPORT = Pattern.compile(
            "import com\\.omninest\\.modules\\.([a-z0-9]+)\\.repository\\.([A-Za-z0-9_.]+);");

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
            Map.entry("THUMBNAIL", "经 FilePostProcessingTaskTracker 生命周期领取"),
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

    /**
     * 任务消息只能先写 Outbox，再由派发器发 Broker。
     *
     * <p>在事务里直发 RabbitMQ 有两个后果：网络 I/O 被圈进数据库事务，
     * 以及 Broker 瞬断时那批消息永久丢失、无法重试。批量入口尤其危险，
     * 因为它把丢失放大成"后半批全没"。</p>
     */
    @Test
    @DisplayName("业务代码不得直发任务消息，必须落 task_dispatches")
    void taskMessagesMustBeWrittenToOutboxBeforePublishing() throws IOException {
        List<String> violations = new ArrayList<>();
        for (Path file : mainJavaFiles()) {
            String relativePath = relative(file);
            if (relativePath.endsWith("RabbitDomainEventPublisher.java")
                    || relativePath.endsWith("DomainEventPublisher.java")) {
                continue;
            }
            if (Files.readString(file).contains(".publishTask(")) {
                violations.add(relativePath);
            }
        }
        assertThat(violations)
                .as("任务消息必须经 TaskDispatchService 落 Outbox，禁止直连 Broker")
                .isEmpty();
    }

    /**
     * 手动 ACK 消费者的领取与失败回写都必须有兜底。
     *
     * <p>{@code AcknowledgeMode.MANUAL} 下容器不会替监听器补发 ACK/NACK：
     * {@code begin()} 写在 try 外、或 {@code handleFailure} 自身抛错时没有
     * {@code basicNack}，消息就永久停在 Unacked，攒满预取额度后整条队列停工。</p>
     */
    @Test
    @DisplayName("手动 ACK 消费者必须把任务领取放进 try 并为失败回写留 nack 兜底")
    void manualAckTaskConsumersMustNackOnStateFailure() throws IOException {
        List<String> violations = new ArrayList<>();
        for (Path file : mainJavaFiles()) {
            String content = Files.readString(file);
            if (!content.contains("taskTracker.begin(")) {
                continue;
            }
            if (!content.contains("TrackedTask tracked = null;") || !content.contains("basicNack")) {
                violations.add(relative(file));
            }
        }
        assertThat(violations)
                .as("领取必须在 try 内（tracked 先置 null），且失败回写异常时必须 basicNack 转死信")
                .isEmpty();
    }

    /**
     * 配额写操作只能通过配额服务。
     *
     * <p>直接调 {@code UserStorageCommand} 会绕过用户资料缓存失效，
     * 用户在缓存恢复前看到的仍是旧用量；同一条链路的加减口径也会分叉。</p>
     */
    @Test
    @DisplayName("配额加减必须经 StorageQuotaService，不得直接改账户用量")
    void quotaWritesMustGoThroughQuotaService() throws IOException {
        List<String> violations = new ArrayList<>();
        for (Path file : mainJavaFiles()) {
            String relativePath = relative(file);
            if (relativePath.endsWith("StorageQuotaService.java")
                    || relativePath.endsWith("StorageQuotaReservationService.java")) {
                continue;
            }
            String content = Files.readString(file);
            if (content.contains("userStorageCommand.incrementUsage(")
                    || content.contains("userStorageCommand.decrementUsage(")
                    || content.contains("userStorageCommand.tryReserveStorage(")
                    || content.contains("userStorageCommand.settleStorageReservation(")
                    || content.contains("userStorageCommand.reconcileUsage(")) {
                violations.add(relativePath);
            }
        }
        assertThat(violations)
                .as("绕过配额服务的用量写入不会淘汰资料缓存，前端配额显示会长期失真")
                .isEmpty();
    }

    /**
     * 仓储只能被它所属的 Maven 模块注入。
     *
     * <p>跨模块直接注入仓储会让"service 接口或领域事件"这条边界形同虚设：改一个模块的
     * 表结构会连带打挂另一个模块，正是深水区耦合的入口。仓库现状是零违例，因此闸门
     * 不留允许清单——出现违例就必须先在属主模块补一个只读端口。</p>
     */
    @Test
    @DisplayName("不得跨 Maven 模块注入其他模块的仓储")
    void repositoryImportsMustStayWithinOwningModule() throws IOException {
        Path root = backendRoot();
        Map<String, Set<String>> ownerByPackage = new HashMap<>();
        for (Path module : ownedModules(root)) {
            Path modulesDir = module.resolve("src/main/java/com/omninest/modules");
            if (!Files.isDirectory(modulesDir)) {
                continue;
            }
            try (Stream<Path> children = Files.list(modulesDir)) {
                children.filter(Files::isDirectory)
                        .forEach(child -> ownerByPackage
                                .computeIfAbsent(child.getFileName().toString(), key -> new HashSet<>())
                                .add(module.getFileName().toString()));
            }
        }

        List<String> violations = new ArrayList<>();
        for (Path file : mainJavaFiles()) {
            String module = relative(file).split("/")[0];
            for (String line : Files.readAllLines(file)) {
                Matcher matcher = CROSS_MODULE_REPOSITORY_IMPORT.matcher(line.trim());
                if (!matcher.matches()) {
                    continue;
                }
                Set<String> owners = ownerByPackage.getOrDefault(matcher.group(1), Set.of());
                if (!owners.isEmpty() && !owners.contains(module)) {
                    violations.add(relative(file) + " -> " + matcher.group(2));
                }
            }
        }

        assertThat(violations)
                .as("跨模块访问数据层必须经属主模块的 service 端口，不能让表结构外溢")
                .isEmpty();
    }

    /**
     * 会真的走网络的接收者类型与其远程方法。
     *
     * <p>只收“发出网络请求”的方法：MinIO 预签名是本地计算，不在其中；{@code getObject}、
     * {@code putObject}、{@code copyObject}、{@code removeObject} 这类才算。</p>
     */
    private static final Map<String, List<String>> REMOTE_IO_METHODS_BY_RECEIVER_TYPE = Map.of(
            "ObjectStorageClient", List.of(
                    "getObject", "putObject", "copyObject", "removeObject", "objectExists", "listObjects",
                    "objectSize", "abortMultipartUpload", "completeMultipartUpload"),
            "DerivedAssetStorageService", List.of(
                    "store", "storeRemote", "deleteOwned", "deleteOwnedBatch", "deleteDerivedFileNode"),
            "FileContentAccessService", List.of(
                    "open", "openRange", "openAuthorizedMediaStream", "openAuthorizedMediaResource"),
            "FileQueryService", List.of(
                    "openOwnedFileContent", "openReadableFileContent", "openDownloadableFileContent",
                    "openDownloadableFileRange"),
            "FilePlaybackContentService", List.of("openFileContent", "openFileRange"),
            "FileDownloadContentService", List.of(
                    "openOwnedFileContent", "openReadableFileContent", "openDownloadableFileContent",
                    "openDownloadableFileRange"),
            "ExternalStorageService", List.of("deactivateRemote", "activateRemote"));

    private static final Pattern TRANSACTIONAL_FIELD =
            Pattern.compile("private final ([A-Za-z0-9_]+)(?:<[^>]*>)?\\s+([a-z][A-Za-z0-9_]*)\\s*;");

    private static final Pattern TRANSACTIONAL_METHOD_DECLARATION =
            Pattern.compile("^\\s{4}(?:public|protected)\\s+(?:static\\s+)?[\\w<>\\[\\],.? ]+\\s+(\\w+)\\s*\\(.*$");

    /**
     * 远程内容读写不得落在数据库事务内。
     *
     * <p>事务里的对象存储调用会让线程在整个网络往返期间占着数据库连接，而派生资产落库
     * 自己还要再开一个独立事务：生产配置里 worker 只有 6 个连接、scheduler 只有 4 个，
     * 并发任务这样叠加就会一起卡在连接池上。鉴权与定位查询留在各自的短事务里，
     * 取流、上传与删除必须在事务之外发起。</p>
     *
     * <p>判据是“方法确实处于事务中”：方法级 {@code @Transactional} 优先，写了
     * {@code NOT_SUPPORTED} 视为已显式挂起；没有方法级注解时才继承类级注解。</p>
     */
    @Test
    @DisplayName("远程内容 IO 必须落在数据库事务之外")
    void remoteContentIoMustStayOutsideTransactions() throws IOException {
        List<String> violations = new ArrayList<>();
        for (Path file : mainJavaFiles()) {
            violations.addAll(transactionalRemoteIoCalls(file));
        }
        assertThat(violations)
                .as("事务内的对象存储与 Rclone 调用会长时间占用连接，并发时直接耗尽连接池")
                .isEmpty();
    }

    private static List<String> transactionalRemoteIoCalls(Path file) throws IOException {
        List<String> lines = Files.readAllLines(file);
        Map<String, String> receivers = new HashMap<>();
        for (String line : lines) {
            Matcher matcher = TRANSACTIONAL_FIELD.matcher(line.trim());
            if (matcher.find()) {
                receivers.put(matcher.group(2), matcher.group(1));
            }
        }
        List<String> banned = new ArrayList<>();
        receivers.forEach((name, type) -> {
            List<String> methods = REMOTE_IO_METHODS_BY_RECEIVER_TYPE.get(type);
            if (methods != null) {
                banned.add("\\b" + name + "\\.(" + String.join("|", methods) + ")\\(");
            }
        });
        if (banned.isEmpty()) {
            return List.of();
        }

        String relativePath = relative(file);
        boolean classTransactional = classLevelTransaction(lines);
        List<String> violations = new ArrayList<>();
        for (int index = 0; index < lines.size(); index++) {
            Matcher declaration = TRANSACTIONAL_METHOD_DECLARATION.matcher(lines.get(index));
            if (!declaration.matches()) {
                continue;
            }
            List<String> annotations = precedingAnnotations(lines, index);
            boolean methodTransactional = annotations.stream().anyMatch(value -> value.startsWith("@Transactional"));
            boolean suspended = annotations.stream()
                    .anyMatch(value -> value.startsWith("@Transactional") && value.contains("NOT_SUPPORTED"));
            boolean inTransaction = methodTransactional ? !suspended : classTransactional;
            if (!inTransaction) {
                continue;
            }
            String body = methodBody(lines, index);
            for (String pattern : banned) {
                Matcher matcher = Pattern.compile(pattern).matcher(body);
                if (matcher.find()) {
                    violations.add(relativePath + "#" + declaration.group(1) + " -> " + matcher.group());
                }
            }
        }
        return violations;
    }

    /** 类级 {@code @Transactional}：注解写在文件首列，紧跟在类型声明之前。 */
    private static boolean classLevelTransaction(List<String> lines) {
        for (String line : lines) {
            if (line.startsWith("@Transactional")) {
                return !line.contains("NOT_SUPPORTED");
            }
            if (line.startsWith("public class") || line.startsWith("class ")
                    || line.startsWith("public final class") || line.startsWith("public abstract class")) {
                return false;
            }
        }
        return false;
    }

    /**
     * 取方法声明上方连续的注解行；注解与方法声明之间只允许出现空行或其他注解。
     */
    private static List<String> precedingAnnotations(List<String> lines, int declarationIndex) {
        List<String> annotations = new ArrayList<>();
        for (int index = declarationIndex - 1; index >= 0; index--) {
            String line = lines.get(index).trim();
            if (line.isEmpty()) {
                continue;
            }
            if (line.startsWith("@")) {
                annotations.add(0, line);
                continue;
            }
            break;
        }
        return annotations;
    }

    /**
     * 从方法声明行按大括号配对取出方法体。
     */
    private static final Pattern COALESCE_EMPTY_STRING_INSIDE_LOWER_LIKE = Pattern.compile(
            "lower\\s*\\(\\s*coalesce\\s*\\(\\s*[a-zA-Z0-9_.]+\\s*,\\s*''\\s*\\)\\s*\\)\\s*like",
            Pattern.CASE_INSENSITIVE);

    @Test
    @DisplayName("JPQL 模糊搜索不得用 coalesce(col, '') 包裹单列以免破坏 pg_trgm GIN 索引")
    void trgmLikeQueriesMustNotWrapColumnInEmptyStringCoalesce() throws IOException {
        List<String> violations = new ArrayList<>();
        for (Path file : mainJavaFiles()) {
            String name = file.getFileName().toString();
            if (!name.endsWith("Repository.java") && !name.endsWith("Queries.java")) {
                continue;
            }
            if (COALESCE_EMPTY_STRING_INSIDE_LOWER_LIKE.matcher(Files.readString(file)).find()) {
                violations.add(relative(file));
            }
        }
        assertThat(violations)
                .as("lower(coalesce(col, '')) 与 lower(col) gin_trgm_ops 索引表达式不匹配，会导致全表扫描")
                .isEmpty();
    }

    @Test
    @DisplayName("阅读器离线幂等创建的 REQUIRES_NEW 子事务必须同时包含同步事件写入")
    void readerIdempotentCreateMustRecordSyncEventInsideNewTransaction() throws IOException {
        Map<String, String> requiredCallByService = Map.of(
                "omninest-media/src/main/java/com/omninest/modules/reader/service/ReaderAnnotationService.java",
                "recordAnnotationEvent(",
                "omninest-media/src/main/java/com/omninest/modules/reader/service/ReaderBookmarkService.java",
                "recordBookmarkEvent(",
                "omninest-media/src/main/java/com/omninest/modules/reader/service/ReaderNoteService.java",
                "recordNoteEvent(");
        List<String> violations = new ArrayList<>();
        for (var entry : requiredCallByService.entrySet()) {
            List<String> lines = Files.readAllLines(backendRoot().resolve(entry.getKey()));
            for (int index = 0; index < lines.size(); index++) {
                if (lines.get(index).contains("saveInNewTransaction(")
                        && lines.get(index).contains("private ")) {
                    if (!methodBody(lines, index).contains(entry.getValue())) {
                        violations.add(entry.getKey() + "#saveInNewTransaction 缺少 " + entry.getValue());
                    }
                }
            }
        }
        assertThat(violations)
                .as("实体落库与同步事件必须处于同一 REQUIRES_NEW 事务，防止外层回滚丢同步事件")
                .isEmpty();
    }

    @Test
    @DisplayName("入库终态失败结算必须清理隔离桶物理对象")
    void settleTerminalFailureMustRemoveQuarantineObject() throws IOException {
        Path promotionService = backendRoot().resolve(
                "omninest-file/src/main/java/com/omninest/modules/file/service/FileIngressPromotionService.java");
        List<String> lines = Files.readAllLines(promotionService);
        for (int index = 0; index < lines.size(); index++) {
            if (lines.get(index).contains("private void settleTerminalFailure(")) {
                assertThat(methodBody(lines, index))
                        .as("settleTerminalFailure 必须统一清理隔离桶物理对象，防止恶意或失败文件永久滞留磁盘")
                        .contains("removeObjectQuietly(quarantineKey(item)");
                return;
            }
        }
        throw new AssertionError("未找到 FileIngressPromotionService#settleTerminalFailure");
    }

    @Test
    @DisplayName("会话吊销的数据库权威列不得被 Redis 异常回滚")
    void sessionRevocationMustCommitDatabaseBeforeCache() throws IOException {
        Path service = backendRoot().resolve(
                "omninest-system/src/main/java/com/omninest/modules/user/service/SessionRevocationService.java");
        List<String> lines = Files.readAllLines(service);
        for (int index = 0; index < lines.size(); index++) {
            if (!lines.get(index).contains("public void invalidateAccessTokensBefore(")) {
                continue;
            }
            String previous = index > 0 ? lines.get(index - 1) : "";
            assertThat(previous)
                    .as("数据库截止时间必须由 REQUIRES_NEW writer 独立提交，方法本身不得包事务")
                    .doesNotContain("@Transactional");
            String body = methodBody(lines, index);
            assertThat(body)
                    .as("必须先提交数据库权威列，再在 try/catch 中写 Redis")
                    .contains("persistAccessCutoff")
                    .contains("catch (RuntimeException");
            return;
        }
        throw new AssertionError("未找到 SessionRevocationService#invalidateAccessTokensBefore");
    }

    @Test
    @DisplayName("分片确认不得重新引入会话悲观锁与全量分片查询")
    void completePartMustUseAtomicUpdates() throws IOException {
        Path service = backendRoot().resolve(
                "omninest-file/src/main/java/com/omninest/modules/file/service/FileUploadSessionService.java");
        List<String> lines = Files.readAllLines(service);
        for (int index = 0; index < lines.size(); index++) {
            if (!lines.get(index).contains("public FileUploadPartsDto completePart(")) {
                continue;
            }
            String body = methodBody(lines, index);
            assertThat(body)
                    .as("3 路并发分片确认不得对会话行加悲观锁或全量读取分片")
                    .contains("markPartCompleted")
                    .contains("incrementUploadedParts")
                    .doesNotContain("findForUpdateByUploadIdAndOwnerUserId")
                    .doesNotContain("findByUploadSessionIdOrderByPartNumber");
            return;
        }
        throw new AssertionError("未找到 FileUploadSessionService#completePart");
    }

    @Test
    @DisplayName("上传完成派发扫描必须在调用方事务内创建入库记录")
    void dispatchSecurityScanMustUseMandatoryTransaction() throws IOException {
        Path service = backendRoot().resolve(
                "omninest-file/src/main/java/com/omninest/modules/file/service/FileUploadSessionService.java");
        List<String> lines = Files.readAllLines(service);
        for (int index = 0; index < lines.size(); index++) {
            if (!lines.get(index).contains("private FileUploadCompleteResultDto dispatchSecurityScan(")) {
                continue;
            }
            String body = methodBody(lines, index);
            assertThat(body)
                    .as("入库记录必须与扫描任务、会话状态同事务提交，不能先独立提交再回滚外层")
                    .contains("openWithinTransaction(")
                    .doesNotContain("ingressLifecycleService.open(");
            return;
        }
        throw new AssertionError("未找到 FileUploadSessionService#dispatchSecurityScan");
    }

    private static String methodBody(List<String> lines, int declarationIndex) {
        int depth = 0;
        boolean opened = false;
        StringBuilder body = new StringBuilder();
        for (int index = declarationIndex; index < lines.size(); index++) {
            String line = lines.get(index);
            for (int cursor = 0; cursor < line.length(); cursor++) {
                char character = line.charAt(cursor);
                if (character == '{') {
                    depth++;
                    opened = true;
                } else if (character == '}') {
                    depth--;
                }
            }
            if (opened) {
                body.append(line).append('\n');
            }
            if (opened && depth <= 0) {
                return body.toString();
            }
        }
        return body.toString();
    }

    private static List<Path> ownedModules(Path root) throws IOException {
        try (Stream<Path> children = Files.list(root)) {
            return children.filter(Files::isDirectory)
                    .filter(path -> path.getFileName().toString().startsWith("omninest-"))
                    .toList();
        }
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
