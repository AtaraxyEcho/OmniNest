package com.omninest.app.migration;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 事务嵌套与后台任务生命周期闸门。
 *
 * <p>本轮修复的共同根因是"主线程已经持有连接，又申请第二条连接"以及
 * "无任务记录的长任务脱离心跳/锁"。这些模式单看每一处都合理，合起来会在
 * 虚拟线程并发下变成连接池死锁或重复执行，因此用静态契约钉住。</p>
 *
 * @author OmniNest
 */
class NestedTransactionDeadlockRatchetTest {

    private static final Pattern TRANSACTIONAL_CREATE = Pattern.compile(
            "@Transactional[\\s\\S]{0,160}?public\\s+\\w+\\s+(createAnnotation|createBookmark|createNote)\\(");

    @Test
    @DisplayName("Reader 创建入口不得叠加外层事务后再走 REQUIRES_NEW")
    void readerCreateMustNotNestNewTransaction() throws IOException {
        Path readerServiceDirectory = backendRoot()
                .resolve("omninest-media/src/main/java/com/omninest/modules/reader/service");
        List<String> violations = new ArrayList<>();
        for (String fileName : List.of(
                "ReaderAnnotationService.java", "ReaderBookmarkService.java", "ReaderNoteService.java")) {
            String content = Files.readString(readerServiceDirectory.resolve(fileName));
            if (TRANSACTIONAL_CREATE.matcher(content).find()) {
                violations.add(fileName);
            }
            assertThat(content).contains("PROPAGATION_REQUIRES_NEW");
        }
        assertThat(violations)
                .as("外层事务持连接等待 REQUIRES_NEW 的第二条连接会耗尽连接池")
                .isEmpty();
    }

    @Test
    @DisplayName("全部 Worker 恢复调度器必须持有分布式锁")
    void everyRecoverySchedulerMustHoldDistributedLock() throws IOException {
        List<String> violations = new ArrayList<>();
        try (Stream<Path> files = Files.walk(backendRoot().resolve("omninest-worker/src/main/java"))) {
            for (Path file : files.filter(path -> path.getFileName().toString().endsWith("RecoveryScheduler.java"))
                    .toList()) {
                if (!Files.readString(file).contains("distributedLock.tryLock")) {
                    violations.add(file.getFileName().toString());
                }
            }
        }
        assertThat(violations)
                .as("多实例下无锁恢复会并发重投同一批超时任务")
                .isEmpty();
    }

    @Test
    @DisplayName("文件后处理任务追踪必须把 RUNNING 视为活跃")
    void postProcessingTrackerMustTreatRunningAsActive() throws IOException {
        String content = Files.readString(backendRoot().resolve(
                "omninest-worker/src/main/java/com/omninest/worker/file/FilePostProcessingTaskTracker.java"));
        assertThat(content)
                .contains("ACTIVE_STATUSES")
                .contains("\"RUNNING\"");
    }

    @Test
    @DisplayName("配额通知必须在提交后异步投递")
    void quotaNotificationMustBeDispatchedAfterCommit() throws IOException {
        String content = Files.readString(backendRoot().resolve(
                "omninest-system/src/main/java/com/omninest/modules/quota/service/StorageQuotaService.java"));
        assertThat(content)
                .contains("afterCommit")
                .contains("quotaNotificationDispatcher.dispatch");
        assertThat(content).doesNotContain("notificationService.notifyOrLog");
    }

    @Test
    @DisplayName("媒体派生资源接口必须为 HEAD 预检关闭流")
    void mediaAssetControllerMustCloseStreamsForHead() throws IOException {
        String content = Files.readString(backendRoot().resolve(
                "omninest-media/src/main/java/com/omninest/modules/video/controller/MediaPublicContentController.java"));
        assertThat(content)
                .contains("HttpMethod.HEAD.matches(request.getMethod())")
                .contains("if (headOnly)");
    }

    @Test
    @DisplayName("分片重传必须刷新已完成分片的 ETag")
    void completedPartReuploadMustRefreshETag() throws IOException {
        String repository = Files.readString(backendRoot().resolve(
                "omninest-file/src/main/java/com/omninest/modules/file/repository/FileUploadPartRepository.java"));
        String service = Files.readString(backendRoot().resolve(
                "omninest-file/src/main/java/com/omninest/modules/file/service/FileUploadSessionService.java"));
        assertThat(repository).contains("updateCompletedPartETag");
        assertThat(service).contains("updateCompletedPartETag(");
    }

    @Test
    @DisplayName("晋升失败不得删除隔离桶中的唯一源对象")
    void promotionFailureMustKeepQuarantineSource() throws IOException {
        String content = Files.readString(backendRoot().resolve(
                "omninest-file/src/main/java/com/omninest/modules/file/service/FileIngressPromotionService.java"));
        // 晋升的瞬时失败路径删掉隔离对象会让重试永久 NoSuchKey；
        // 确定性终态失败（病毒/摘要不符/配额不足）仍按设计清理隔离对象。
        assertThat(content).doesNotContain("清理文件晋升失败隔离对象失败");
        assertThat(content).contains("清理入库终态失败隔离对象失败");
    }

    @Test
    @DisplayName("转码失败必须在各阶段清理已入库的派生文件")
    void transcodeFailureMustDeleteOrphanDerived() throws IOException {
        String content = Files.readString(backendRoot().resolve(
                "omninest-media/src/main/java/com/omninest/modules/video/service/TranscodeExecutionService.java"));
        long cleanupCalls = content.lines().filter(line -> line.contains("deleteOrphanDerived(")).count();
        assertThat(cleanupCalls)
                .as("H265/音频/Web 优化三条链路都必须在失败分支回收派生文件")
                .isGreaterThanOrEqualTo(7);
    }

    @Test
    @DisplayName("外部导入必须挂载任务心跳")
    void externalImportMustHeartbeat() throws IOException {
        String content = Files.readString(backendRoot().resolve(
                "omninest-file/src/main/java/com/omninest/modules/file/service/ExternalImportExecutionService.java"));
        assertThat(content).contains("taskHeartbeatRunner.start(");
    }

    private Path backendRoot() {
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
}
