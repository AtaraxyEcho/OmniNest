package com.omninest.app.architecture;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

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
 * compose 网络拓扑契约测试（SEC-10 L3 的防退化守卫）。
 *
 * <p>分区本身是一次配置改动，坏得最快的方式是后来加服务或改网络时没人拦。这里把两张
 * compose 的"服务 → 网络"成员表逐字钉住，并钉三条实测出来的物理约束：</p>
 *
 * <ul>
 *   <li>出网执行体（aria2、rclone）只允许在 {@code egress}，数据面与 nginx 一律不得进 {@code egress}；</li>
 *   <li>容器模式的 ffmpeg 独占 internal 的 {@code media}，minio 双挂 {@code default} 与 {@code media}
 *       供它取预签名地址——媒体内容里内嵌的远程引用由 ffmpeg 自己去取，这张网没有公网路由也不解析
 *       数据面服务名，二级出网才在拓扑层封死；</li>
 *   <li>{@code internal} 与发布端口互斥：实测"只挂 internal 网 + 发布端口"的组合下发布端口根本不生效
 *       （容器 {@code Ports} 为空、宿主连不上）。所以约束是"全部网络都 internal 的服务不得发布端口"，
 *       双挂非 internal 网的 minio 属合法形状。</li>
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
    private static final String MEDIA = "media";
    private static final Path REPO_ROOT = findRepoRoot();

    /** 每张 compose 允许出现的全部服务，以及它们在 egress / media 上的成员；两者都不在的服务即留在 default。 */
    private static final Map<String, ExpectedTopology> FILES = Map.of(
            "deploy/dev/docker-compose.yml", new ExpectedTopology(
                    Set.of("postgres", "redis", "rabbitmq", "minio", "aria2", "clamav", "netease-music-api",
                            "ffmpeg", "rclone", "ai-sidecar"),
                    Set.of("aria2", "rclone"),
                    Set.of("ffmpeg", "minio")),
            "deploy/prod/docker-compose.yml", new ExpectedTopology(
                    Set.of("nginx", "certbot", "backend-api", "backend-worker", "backend-scheduler", "postgres",
                            "redis", "rabbitmq", "minio", "ffmpeg", "aria2", "clamav", "netease-music-api",
                            "rclone", "ai-sidecar"),
                    Set.of("aria2", "rclone", "backend-api", "backend-worker", "backend-scheduler"),
                    Set.of("ffmpeg", "minio"))
    );

    private record ExpectedTopology(Set<String> services, Set<String> egressMembers, Set<String> mediaMembers) {
    }

    @Test
    @DisplayName("出网执行体与 ffmpeg 的网络成员表逐字保持已知")
    void networkMembershipStaysTheKnownSet() throws IOException {
        for (Map.Entry<String, ExpectedTopology> entry : FILES.entrySet()) {
            String file = entry.getKey();
            Map<String, Object> root = load(REPO_ROOT.resolve(file));
            Map<String, Set<String>> membership = readMembership(root);
            ExpectedTopology expected = entry.getValue();

            assertEquals(new TreeSet<>(expected.services()), new TreeSet<>(membership.keySet()),
                    file + " 的服务集合变化了：新增服务必须同时决定它进不进 egress/media，"
                            + "否则分区会静默漏掉这个服务");

            assertEquals(new TreeSet<>(expected.egressMembers()), membersOf(membership, EGRESS),
                    file + " 的 " + EGRESS + " 成员表被改动：只有出网执行体与其调用方应在其中");

            assertEquals(new TreeSet<>(expected.mediaMembers()), membersOf(membership, MEDIA),
                    file + " 的 " + MEDIA + " 成员表被改动：ffmpeg 必须独占它，minio 双挂供它取地址");

            membership.forEach((service, networks) -> {
                boolean special = expected.egressMembers().contains(service)
                        || expected.mediaMembers().contains(service);
                if (!special) {
                    assertTrue(networks.contains("default"),
                            file + " 的 " + service + " 应当留在 default 上，实际为 " + networks);
                }
            });
        }
    }

    @Test
    @DisplayName("internal 网与发布端口的互斥")
    void internalOnlyServicesNeverPublishPorts() throws IOException {
        for (String file : FILES.keySet()) {
            Path compose = REPO_ROOT.resolve(file);
            Map<String, Object> root = load(compose);
            Set<String> internalNetworks = internalNetworks(root);
            readMembership(root).forEach((service, networks) -> {
                if (!hasPublishedPorts(compose, service)) {
                    return;
                }
                boolean allInternal = internalNetworks.containsAll(networks);
                if (allInternal) {
                    fail(file + " 的服务 " + service + " 只挂在 internal 网 " + networks
                            + " 上却发布了端口：实测该组合下发布端口不生效，宿主侧会静默连不上");
                }
            });
        }
    }

    @Test
    @DisplayName("egress 可出公网，media 必须保持 internal")
    void partitionNetworkFlagsStayAsMeasured() throws IOException {
        for (String file : FILES.keySet()) {
            Map<String, Object> root = load(REPO_ROOT.resolve(file));
            Object networks = root.get("networks");
            assertTrue(networks instanceof Map<?, ?> map
                            && map.containsKey(EGRESS) && map.containsKey(MEDIA),
                    file + " 缺少 egress 或 media 网络定义");
            Object egress = ((Map<?, ?>) networks).get(EGRESS);
            if (egress instanceof Map<?, ?> body) {
                assertTrue(!Boolean.TRUE.equals(body.get("internal")),
                        file + " 的 " + EGRESS + " 被设成 internal：aria2 与 rclone 必须能出公网");
            }
            Object media = ((Map<?, ?>) networks).get(MEDIA);
            assertTrue(media instanceof Map<?, ?> body && Boolean.TRUE.equals(body.get("internal")),
                    file + " 的 " + MEDIA + " 不再是 internal：ffmpeg 内容内嵌引用的二级出网重新开放");
        }
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
        Object services = root.get("services");
        assertTrue(services instanceof Map, "compose 缺少 services 段");
        Map<String, Set<String>> membership = new LinkedHashMap<>();
        ((Map<String, Object>) services).forEach((service, body) -> {
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

    private static Set<String> internalNetworks(Map<String, Object> root) {
        Set<String> internal = new LinkedHashSet<>();
        if (root.get("networks") instanceof Map<?, ?> networks) {
            networks.forEach((name, body) -> {
                if (body instanceof Map<?, ?> definition && Boolean.TRUE.equals(definition.get("internal"))) {
                    internal.add(String.valueOf(name));
                }
            });
        }
        return internal;
    }

    private static boolean hasPublishedPorts(Path compose, String service) {
        try {
            Object body = ((Map<String, Object>) load(compose).get("services")).get(service);
            return body instanceof Map<?, ?> definition && definition.get("ports") instanceof List<?> list
                    && !list.isEmpty();
        } catch (IOException exception) {
            throw new IllegalStateException("读取 compose 失败: " + compose, exception);
        }
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
