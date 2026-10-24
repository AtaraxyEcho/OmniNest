package com.omninest.app.architecture;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.LoaderOptions;
import org.yaml.snakeyaml.Yaml;

/**
 * compose 网络与媒体临时卷契约测试（SEC-10 L3 的防退化守卫）。
 *
 * <p>分区本身是一次配置改动，坏得最快的方式是后来加服务或改网络时没人拦。这里把两张
 * compose 的"服务 → 网络"成员表逐字钉住，并钉住媒体处理的部署形态：</p>
 *
 * <ul>
 *   <li>出网执行体（rclone）只允许在 {@code egress}，数据面与 nginx 一律不得进 {@code egress}；</li>
 *   <li>不再维护独立的 ffmpeg 容器与 {@code media} internal 网，转码/探测都在后端容器内执行；</li>
 *   <li>探测与转码临时文件必须挂到后端命名卷，否则数 GB 视频会写在容器 OverlayFS 上。</li>
 * </ul>
 *
 * <p>解析整份 YAML 而非用 docker 查询：compose 的锚点合并（后端三角色共用
 * {@code x-backend-service}）由加载器完成，因此表里出现的就是实际生效的成员关系；
 * 同时 profile 服务也在表内，避免"profile 服务被普通 up -d 留在旧网络"这类盲区无法被发现。</p>
 *
 * @author OmniNest
 */
class ComposeNetworkTopologyTest {

    private static final String EGRESS = "egress";
    private static final Path REPO_ROOT = findRepoRoot();
    private static final String PROBE_VOLUME = "omninest-probe-cache:/tmp/omninest-probe";
    private static final String TRANSCODE_VOLUME =
            "omninest-transcode-cache:/tmp/omninest-processing/transcode";

    /** 每张 compose 允许出现的全部服务，以及它们在 egress 上的成员；不在 egress 的服务即留在 default。 */
    private static final Map<String, ExpectedTopology> FILES = Map.of(
            "deploy/dev/docker-compose.yml", new ExpectedTopology(
                    Set.of("postgres", "redis", "rabbitmq", "minio", "clamav", "netease-music-api",
                            "rclone", "vision-sidecar"),
                    Set.of("rclone")),
            "deploy/prod/docker-compose.yml", new ExpectedTopology(
                    Set.of("nginx", "certbot", "backend-api", "backend-worker", "backend-scheduler", "postgres",
                            "redis", "rabbitmq", "minio", "clamav", "netease-music-api",
                            "rclone", "vision-sidecar"),
                    Set.of("rclone", "backend-api", "backend-worker", "backend-scheduler"))
    );

    private record ExpectedTopology(Set<String> services, Set<String> egressMembers) {
    }

    @Test
    @DisplayName("出网执行体的网络成员表逐字保持已知")
    void networkMembershipStaysTheKnownSet() throws IOException {
        for (Map.Entry<String, ExpectedTopology> entry : FILES.entrySet()) {
            String file = entry.getKey();
            Map<String, Object> root = load(REPO_ROOT.resolve(file));
            Map<String, Set<String>> membership = readMembership(root);
            ExpectedTopology expected = entry.getValue();

            assertEquals(new TreeSet<>(expected.services()), new TreeSet<>(membership.keySet()),
                    file + " 的服务集合变化了：新增服务必须同时决定它进不进 egress，"
                            + "否则分区会静默漏掉这个服务");

            assertEquals(new TreeSet<>(expected.egressMembers()), membersOf(membership, EGRESS),
                    file + " 的 " + EGRESS + " 成员表被改动：只有出网执行体与其调用方应在其中");

            membership.forEach((service, networks) -> {
                if (!expected.egressMembers().contains(service)) {
                    assertTrue(networks.contains("default"),
                            file + " 的 " + service + " 应当留在 default 上，实际为 " + networks);
                }
            });
        }
    }

    @Test
    @DisplayName("独立 ffmpeg 容器与 media 内网已移除")
    void ffmpegIsolationContainerIsGone() throws IOException {
        for (String file : FILES.keySet()) {
            Map<String, Object> root = load(REPO_ROOT.resolve(file));
            Map<String, Object> services = services(root);
            assertFalse(services.containsKey("ffmpeg"), file + " 仍保留闲置的 ffmpeg 容器");
            Object networks = root.get("networks");
            assertTrue(networks instanceof Map<?, ?> map && !map.containsKey("media"),
                    file + " 仍保留 media internal 网，但独立 ffmpeg 容器已不再使用它");
        }
    }

    @Test
    @DisplayName("生产后端把探测与转码临时目录挂到命名卷")
    void backendUsesDedicatedTemporaryVolumes() throws IOException {
        Map<String, Object> root = load(REPO_ROOT.resolve("deploy/prod/docker-compose.yml"));
        Map<String, Object> services = services(root);
        for (String role : List.of("backend-api", "backend-worker")) {
            Object body = services.get(role);
            assertTrue(body instanceof Map<?, ?> definition, "缺少后端角色: " + role);
            List<String> volumes = stringList(((Map<?, ?>) body).get("volumes"));
            assertTrue(volumes.contains(PROBE_VOLUME),
                    role + " 未挂载探测临时卷，ffprobe 首尾窗口会写进 OverlayFS: " + volumes);
            assertTrue(volumes.contains(TRANSCODE_VOLUME),
                    role + " 未挂载转码临时卷，数 GB 视频会写进 OverlayFS: " + volumes);
        }
    }

    @Test
    @DisplayName("生产后端三角色独立且照片批量保留期可配")
    void backendRolesAndBatchRetentionAreConfigured() throws IOException {
        Map<String, Object> root = load(REPO_ROOT.resolve("deploy/prod/docker-compose.yml"));
        Map<String, Object> services = services(root);
        for (String role : List.of("api", "worker", "scheduler")) {
            Map<String, Object> environment = environment(services.get("backend-" + role));
            assertEquals(role, environment.get("OMNINEST_ROLE"),
                    "backend-" + role + " 必须显式声明独立运行角色");
            for (String key : List.of(
                    "PHOTO_BATCH_RETENTION_ENABLED",
                    "PHOTO_BATCH_RETENTION_MAX_AGE",
                    "PHOTO_BATCH_RETENTION_BATCH_SIZE")) {
                assertTrue(environment.containsKey(key),
                        "backend-" + role + " 未继承照片批量保留期配置: " + key);
            }
        }
    }

    @Test
    @DisplayName("egress 可出公网且不存在 internal 数据面网络")
    void egressNetworkStaysNonInternal() throws IOException {
        for (String file : FILES.keySet()) {
            Map<String, Object> root = load(REPO_ROOT.resolve(file));
            Object networks = root.get("networks");
            assertTrue(networks instanceof Map<?, ?> map && map.containsKey(EGRESS),
                    file + " 缺少 egress 网络定义");
            Object egress = ((Map<?, ?>) networks).get(EGRESS);
            if (egress instanceof Map<?, ?> body) {
                assertTrue(!Boolean.TRUE.equals(body.get("internal")),
                        file + " 的 " + EGRESS + " 被设成 internal：rclone 必须能出公网");
            }
        }
    }

    private static Map<String, Object> services(Map<String, Object> root) {
        Object services = root.get("services");
        assertTrue(services instanceof Map, "compose 缺少 services 段");
        return (Map<String, Object>) services;
    }

    private static Map<String, Object> environment(Object service) {
        assertTrue(service instanceof Map<?, ?>, "缺少后端服务定义");
        Object environment = ((Map<?, ?>) service).get("environment");
        assertTrue(environment instanceof Map, "后端服务缺少 environment 段");
        return (Map<String, Object>) environment;
    }

    private static List<String> stringList(Object value) {
        if (!(value instanceof List<?> list)) {
            return List.of();
        }
        return list.stream().map(String::valueOf).toList();
    }

    private static Map<String, Object> load(Path compose) throws IOException {
        LoaderOptions options = new LoaderOptions();
        try (InputStream input = Files.newInputStream(compose)) {
            Object parsed = new Yaml(options).load(input);
            assertTrue(parsed instanceof Map, "compose 文件根节点不是映射: " + compose);
            return (Map<String, Object>) parsed;
        }
    }

    /**
     * 服务 → 网络成员。未写 networks 的服务按 compose 语义落在 default；锚点合并由加载器完成。
     */
    private static Map<String, Set<String>> readMembership(Map<String, Object> root) {
        Map<String, Set<String>> membership = new LinkedHashMap<>();
        services(root).forEach((service, body) -> {
            Set<String> networks = new LinkedHashSet<>();
            if (body instanceof Map<?, ?> definition && definition.get("networks") != null) {
                Object declared = definition.get("networks");
                if (declared instanceof List<?> list) {
                    list.forEach(item -> networks.add(String.valueOf(item)));
                } else if (declared instanceof Map<?, ?> map) {
                    map.keySet().forEach(item -> networks.add(String.valueOf(item)));
                }
            }
            if (networks.isEmpty()) {
                networks.add("default");
            }
            membership.put(service, networks);
        });
        return membership;
    }

    private static Set<String> membersOf(Map<String, Set<String>> membership, String network) {
        Set<String> members = new TreeSet<>();
        membership.forEach((service, networks) -> {
            if (networks.contains(network)) {
                members.add(service);
            }
        });
        return members;
    }

    private static Path findRepoRoot() {
        Path current = Path.of("").toAbsolutePath();
        while (current != null) {
            if (Files.isRegularFile(current.resolve("deploy/prod/docker-compose.yml"))
                    && Files.isRegularFile(current.resolve("deploy/dev/docker-compose.yml"))) {
                return current;
            }
            current = current.getParent();
        }
        throw new IllegalStateException("未找到包含 deploy/ 的仓库根目录");
    }
}
