package com.omninest.app.architecture;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

/**
 * 出网执行体登记守卫。
 *
 * <p>本项目"会被不可信输入驱动出网"的位置不是一处，而是两类：rclone 远端，
 * 以及后端自己起的 ffmpeg/ffprobe 子进程与 JVM HTTP 客户端。SEC-10 的教训是：
 * 只盯住某一处出网点会漏掉其余位置（ffprobe 会跟随媒体内容里的播放列表引用出网，
 * rclone 会跟随重定向），而新增下一个出网点时没有任何东西会提醒开发者它需要闸门。</p>
 *
 * <p>本测试要求每个出网位置都在登记表里写明它的闸门；闸门说明缺失、或出现未登记的新出网位置，
 * 都让构建变红。登记表只覆盖主源码，测试与端口接口不参与。</p>
 *
 * @author OmniNest
 */
class OutboundExecutorRegistryTest {

    /** 出网位置的识别标记：自建 HTTP 客户端、起子进程、驱动下载器/远端网关。都是代码形状，不匹配注释里的词。 */
    private static final Pattern OUTBOUND_MARKER = Pattern.compile(
            "^import java\\.net\\.http\\.HttpClient;|HttpClient\\.(newBuilder|newHttpClient)"
                    + "|new ProcessBuilder|VideoProcessExecutor|\\.exec\\("
                    + "|RcloneGateway|RcloneRcClient",
            Pattern.MULTILINE
    );

    /** 地址可由数据（而非硬编码常量）决定的位置：必须声明一个真实的地址闸门。 */
    private static final Set<String> DATA_ADDRESSED_SOURCES = Set.of(
            "omninest-file/src/main/java/com/omninest/modules/file/service/DerivedAssetStorageService.java",
            "omninest-file/src/main/java/com/omninest/modules/file/service/ExternalStorageService.java",
            "omninest-file/src/main/java/com/omninest/modules/file/service/ExternalImportExecutionService.java",
            "omninest-media/src/main/java/com/omninest/modules/music/service/MusicStreamGatewayService.java"
    );

    private static final Set<String> ADDRESS_GATES = Set.of(
            "SafeUrlValidator",
            "ExternalStorageEndpointGuard",
            "MusicOnlineSourceUrlPolicy",
            "OutboundEndpointRules"
    );

    private static final Map<String, String> REGISTERED_OUTBOUND_SOURCES = Map.ofEntries(
            Map.entry("omninest-common/src/main/java/com/omninest/common/rclone/RcloneGateway.java",
                    "端口：唯一实现是 RcloneRcClient，远端地址由外部存储账户凭证决定"),
            Map.entry("omninest-infrastructure/src/main/java/com/omninest/common/rclone/RcloneRcClient.java",
                    "RC 端点来自配置；远端地址在文件模块过 ExternalStorageEndpointGuard"),
            Map.entry("omninest-infrastructure/src/main/java/com/omninest/common/ai/AiSidecarClient.java",
                    "端点来自 config-center 的 superAdminOnly 键，自持内网 sidecar 属认可形态"),
            Map.entry("omninest-file/src/main/java/com/omninest/modules/file/service/DerivedAssetStorageService.java",
                    "SafeUrlValidator.requireSafeHttpUrl 逐跳校验后取回派生资源"),
            Map.entry("omninest-file/src/main/java/com/omninest/modules/file/service/ExternalStorageService.java",
                    "ExternalStorageEndpointGuard 校验用户填写的 S3/WebDAV 端点"),
            Map.entry("omninest-file/src/main/java/com/omninest/modules/file/service/ExternalImportExecutionService.java",
                    "沿用 ExternalStorageEndpointGuard 校验过的账户端点；下载产物经 File 入库链路"),
            Map.entry("omninest-file/src/main/java/com/omninest/modules/file/service/ExternalStorageOAuthService.java",
                    "提供方端点为常量；redirect_uri 只作表单字段不外连"),
            Map.entry("omninest-file/src/main/java/com/omninest/modules/file/service/MediaProbeService.java",
                    "ffprobe 子进程；输入是 MediaProbeSourceStager 取出的本地稀疏文件，不吃预签名地址，"
                            + "因此内容里内嵌的远程引用不会被跟随"),
            Map.entry("omninest-infrastructure/src/main/java/com/omninest/common/security/SsrfSafeUrlValidator.java",
                    "闸门本体"),
            Map.entry("omninest-media/src/main/java/com/omninest/modules/music/service/LrclibLyricsService.java",
                    "OutboundEndpointRules.requirePublicEndpoint + Redirect.NEVER"),
            Map.entry("omninest-media/src/main/java/com/omninest/modules/music/service/MusicBrainzMetadataProvider.java",
                    "OutboundEndpointRules.requireConfiguredEndpoint"),
            Map.entry("omninest-media/src/main/java/com/omninest/modules/music/service/MusicStreamGatewayService.java",
                    "MusicOnlineSourceUrlPolicy + 逐跳重定向校验，禁自动跟随"),
            Map.entry("omninest-media/src/main/java/com/omninest/modules/music/service/platform/NeteaseMusicProxy.java",
                    "OutboundEndpointRules.requireConfiguredEndpoint"),
            Map.entry("omninest-media/src/main/java/com/omninest/modules/photos/service/PhotoGeoService.java",
                    "硬编码 Nominatim 端点，仅追加数值坐标"),
            Map.entry("omninest-media/src/main/java/com/omninest/modules/video/service/TmdbMetadataProvider.java",
                    "OutboundEndpointRules.requireConfiguredEndpoint"),
            Map.entry("omninest-media/src/main/java/com/omninest/modules/video/service/VideoProbeService.java",
                    "ffprobe 子进程；先部分下载到本地临时文件再探测"),
            Map.entry("omninest-media/src/main/java/com/omninest/modules/video/service/VideoProcessExecutor.java",
                    "子进程执行、超时与输出回收的统一出口"),
            Map.entry("omninest-media/src/main/java/com/omninest/modules/video/service/VideoStreamService.java",
                    "ffmpeg 实时 remux；输入为我们自己的预签名地址（L2：待评估本地暂存）"),
            Map.entry("omninest-media/src/main/java/com/omninest/modules/video/service/VideoTranscodeService.java",
                    "ffmpeg 转码；输入为我们自己的预签名地址（L2：待评估本地暂存）"),
            Map.entry("omninest-media/src/main/java/com/omninest/modules/backdrop/service/BackdropVideoThumbnailExtractor.java",
                    "ffmpeg 截帧；优先读本地 staging 文件"),
            Map.entry("omninest-worker/src/main/java/com/omninest/worker/runtime/WorkerRuntimeReporter.java",
                    "端点来自 config-center 的 superAdminOnly 键")
    );

    @Test
    void everyOutboundExecutorIsRegisteredWithItsGate() throws IOException {
        Path root = findBackendRoot();
        Set<String> violations = new HashSet<>();
        for (String module : List.of(
                "omninest-common", "omninest-infrastructure", "omninest-system",
                "omninest-file", "omninest-media", "omninest-worker", "omninest-app")) {
            Path sourceRoot = root.resolve(module).resolve("src/main/java");
            if (!Files.isDirectory(sourceRoot)) {
                continue;
            }
            try (Stream<Path> files = Files.walk(sourceRoot)) {
                files.filter(path -> path.toString().endsWith(".java")).forEach(path -> {
                    String relative = normalize(root.relativize(path));
                    try {
                        if (OUTBOUND_MARKER.matcher(Files.readString(path)).find()
                                && !REGISTERED_OUTBOUND_SOURCES.containsKey(relative)) {
                            violations.add(relative);
                        }
                    } catch (IOException exception) {
                        throw new IllegalStateException("读取源码失败: " + relative, exception);
                    }
                });
            }
        }
        assertEquals(Set.of(), violations,
                "新增出网位置必须先进登记表并写明闸门，否则视为未评审的出网面");
    }

    @Test
    void dataAddressedSourcesDeclareARealGate() {
        DATA_ADDRESSED_SOURCES.forEach(relative -> {
            String gate = REGISTERED_OUTBOUND_SOURCES.get(relative);
            assertTrue(gate != null && ADDRESS_GATES.stream().anyMatch(gate::contains),
                    "地址来自数据的出网位置必须声明真实存在的地址闸门: " + relative);
        });
    }

    @Test
    void registryEntriesStillExist() throws IOException {
        Path root = findBackendRoot();
        assertEquals(List.of(), REGISTERED_OUTBOUND_SOURCES.keySet().stream()
                .filter(entry -> !Files.isRegularFile(root.resolve(entry)))
                .toList(), "登记表条目必须对应仍存在的源文件");
    }

    private Path findBackendRoot() {
        Path current = Path.of("").toAbsolutePath();
        while (current != null) {
            if (Files.isDirectory(current.resolve("omninest-file")) && Files.isRegularFile(current.resolve("pom.xml"))) {
                return current;
            }
            current = current.getParent();
        }
        throw new IllegalStateException("未找到 backend 根目录");
    }

    private String normalize(Path path) {
        return path.toString().replace('\\', '/');
    }
}
