package com.omninest.app.architecture;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 校验后端业务包与 Maven 模块的依赖边界。
 *
 * @author OmniNest
 */
class ModuleDependencyBoundaryTest {

    private static final long MAX_PRODUCTION_SOURCE_LINES = 1200;
    private static final long MAX_WORKER_CONSUMER_SOURCE_LINES = 150;
    /** 0.1.0 发布前登记的存量超长源码；禁止新增，拆分完成后移除。 */
    private static final Set<String> ALLOWED_OVERSIZED_SOURCES = Set.of(
            "omninest-worker/src/main/java/com/omninest/worker/tika/TextExtractionConsumer.java",
            "omninest-media/src/main/java/com/omninest/modules/photos/repository/PhotoItemRepository.java",
            "omninest-file/src/main/java/com/omninest/modules/file/service/FileManagerService.java"
    );
    private static final List<String> MODULES = List.of(
            "omninest-common",
            "omninest-infrastructure",
            "omninest-system",
            "omninest-file",
            "omninest-media",
            "omninest-worker",
            "omninest-app"
    );
    private static final Pattern REPOSITORY_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.modules\\.([^.]+)\\.repository\\.([^;]+);",
            Pattern.MULTILINE
    );
    private static final Pattern SERVICE_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.modules\\.([^.]+)\\.service\\.([^;]+);",
            Pattern.MULTILINE
    );
    private static final Pattern BUSINESS_IMPORT_PATTERN = Pattern.compile(
            "^import (com\\.omninest\\.modules\\.[^;]+);",
            Pattern.MULTILINE
    );
    private static final Pattern FEATURE_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.modules\\.([^.]+)\\.[^;]+;",
            Pattern.MULTILINE
    );
    private static final Pattern WORKER_CONSUMER_INFRASTRUCTURE_IMPORT_PATTERN = Pattern.compile(
            "^import (com\\.omninest\\.common\\.(?:ai|config|download|rclone|util)\\.[^;]+);",
            Pattern.MULTILINE
    );
    private static final Pattern SOURCE_FEATURE_PATTERN = Pattern.compile(
            "/com/omninest/modules/([^/]+)/"
    );
    private static final Pattern INTERNAL_DEPENDENCY_PATTERN = Pattern.compile(
            "<groupId>com\\.omninest</groupId>\\s*<artifactId>(omninest-[^<]+)</artifactId>"
    );
    private static final Pattern COMMON_FORBIDDEN_IMPORT_PATTERN = Pattern.compile(
            "^import (org\\.springframework|jakarta\\.|io\\.minio|software\\.amazon|com\\.rabbitmq|"
                    + "com\\.alibaba\\.fastjson2|com\\.fasterxml\\.jackson)[^;]*;",
            Pattern.MULTILINE
    );
    private static final Pattern MINIO_PROPERTIES_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.config\\.MinioProperties;",
            Pattern.MULTILINE
    );
    private static final Pattern REDIS_TOKEN_BUCKET_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.ratelimit\\.RedisTokenBucketRateLimiter;",
            Pattern.MULTILINE
    );
    private static final Pattern REDIS_UTIL_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.util\\.RedisUtil;",
            Pattern.MULTILINE
    );
    private static final Pattern SSRF_VALIDATOR_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.security\\.SsrfSafeUrlValidator;",
            Pattern.MULTILINE
    );
    private static final Pattern UPLOAD_PROPERTIES_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.config\\.UploadProperties;",
            Pattern.MULTILINE
    );
    private static final Pattern RCLONE_PROPERTIES_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.config\\.RcloneProperties;",
            Pattern.MULTILINE
    );
    private static final Pattern RCLONE_CLIENT_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.rclone\\.RcloneRcClient;",
            Pattern.MULTILINE
    );
    private static final Pattern OFFLINE_DOWNLOAD_INFRASTRUCTURE_IMPORT_PATTERN = Pattern.compile(
            "^import (com\\.omninest\\.common\\.config\\.Aria2Properties|"
                    + "com\\.omninest\\.common\\.download\\.Aria2RpcClient|"
                    + "com\\.omninest\\.common\\.download\\.SafeOfflineDownloadSourceResolver);",
            Pattern.MULTILINE
    );
    private static final Pattern CREDENTIAL_CIPHER_IMPLEMENTATION_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.security\\.AesGcmCredentialCipher;",
            Pattern.MULTILINE
    );
    private static final Pattern REDIS_SESSION_IMPLEMENTATION_IMPORT_PATTERN = Pattern.compile(
            "^import (com\\.omninest\\.common\\.security\\.RedisSessionRevocationCache|"
                    + "com\\.omninest\\.common\\.security\\.RedisActiveSessionRegistry);",
            Pattern.MULTILINE
    );
    private static final Pattern REDIS_RUNTIME_CONFIG_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.config\\.RedisRuntimeConfigCache;",
            Pattern.MULTILINE
    );
    private static final Pattern AI_SIDECAR_CLIENT_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.ai\\.AiSidecarClient(?:\\.[^;]+)?;",
            Pattern.MULTILINE
    );
    private static final Pattern SECURITY_PROPERTIES_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.config\\.SecurityProperties;",
            Pattern.MULTILINE
    );
    private static final Pattern HMAC_AUTHENTICATOR_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.security\\.HmacSha256PayloadAuthenticator;",
            Pattern.MULTILINE
    );
    private static final Pattern WEATHER_CONFIG_CENTER_SERVICE_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.modules\\.configcenter\\.service\\.ConfigCenterService;",
            Pattern.MULTILINE
    );
    private static final Pattern USER_PREFERENCE_SERVICE_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.modules\\.preferences\\.service\\.UserPreferenceService;",
            Pattern.MULTILINE
    );
    private static final Pattern NOTIFICATION_SERVICE_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.modules\\.notification\\.service\\.NotificationService;",
            Pattern.MULTILINE
    );
    private static final Pattern VIDEO_SERVICE_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.modules\\.video\\.service\\.[^;]+;",
            Pattern.MULTILINE
    );
    private static final Pattern OBJECT_STORAGE_PRIMITIVE_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.storage\\.(ObjectStorageClient|ObjectStorageKey);",
            Pattern.MULTILINE
    );
    private static final Pattern JWT_AUTHORITY_CONVERTER_IMPORT_PATTERN = Pattern.compile(
            "^import com\\.omninest\\.common\\.security\\.JwtAuthorityConverter;",
            Pattern.MULTILINE
    );
    @Test
    void businessDependencyViolationsMustNotIncrease() throws IOException {
        Set<String> violations = scanBusinessViolations();
        Set<String> allowedViolations = loadAllowedViolations();
        Set<String> unexpected = new TreeSet<>(violations);
        unexpected.removeAll(allowedViolations);
        Set<String> removed = new TreeSet<>(allowedViolations);
        removed.removeAll(violations);

        assertTrue(unexpected.isEmpty(), () -> "发现新增架构违规：\n" + String.join("\n", unexpected));
        assertTrue(removed.isEmpty(), () -> "以下允许项已修复，请从清单删除：\n" + String.join("\n", removed));
    }

    @Test
    void mavenModuleDependenciesMustFollowDeclaredDirection() throws IOException {
        Map<String, Set<String>> expected = Map.of(
                "omninest-common", Set.of(),
                "omninest-infrastructure", Set.of("omninest-common"),
                "omninest-system", Set.of("omninest-common"),
                "omninest-file", Set.of("omninest-common", "omninest-system"),
                "omninest-media", Set.of(
                        "omninest-common", "omninest-infrastructure", "omninest-system", "omninest-file"
                ),
                "omninest-worker", Set.of(
                        "omninest-common", "omninest-infrastructure", "omninest-system", "omninest-file",
                        "omninest-media"
                ),
                "omninest-app", Set.of(
                        "omninest-common", "omninest-infrastructure", "omninest-system", "omninest-file",
                        "omninest-media", "omninest-worker"
                )
        );
        Map<String, Set<String>> actual = new HashMap<>();
        Path root = findBackendRoot();

        for (String module : MODULES) {
            String pom = Files.readString(root.resolve(module).resolve("pom.xml"));
            Matcher matcher = INTERNAL_DEPENDENCY_PATTERN.matcher(pom);
            Set<String> dependencies = new HashSet<>();
            while (matcher.find()) {
                String dependency = matcher.group(1);
                if (MODULES.contains(dependency)) {
                    dependencies.add(dependency);
                }
            }
            actual.put(module, dependencies);
        }

        assertEquals(expected, actual, "Maven 模块依赖方向发生变化，需要先完成架构评审");
    }

    @Test
    void businessFeatureDependenciesMustBeAcyclic() throws IOException {
        Map<String, Set<String>> graph = scanFeatureDependencies();
        Set<String> cyclicEdges = new TreeSet<>();
        for (Map.Entry<String, Set<String>> entry : graph.entrySet()) {
            for (String target : entry.getValue()) {
                if (hasDependencyPath(graph, target, entry.getKey(), new HashSet<>())) {
                    cyclicEdges.add(entry.getKey() + " -> " + target);
                }
            }
        }

        assertTrue(
                cyclicEdges.isEmpty(),
                () -> "业务 Feature 之间存在依赖环，相关依赖边：\n" + String.join("\n", cyclicEdges)
        );
    }

    @Test
    void productionJavaSourcesMustStayWithinSizeLimit() throws IOException {
        Path root = findBackendRoot();
        Set<String> oversizedSources = new TreeSet<>();
        for (String module : MODULES) {
            Path sourceRoot = root.resolve(module).resolve("src/main/java");
            if (!Files.isDirectory(sourceRoot)) {
                continue;
            }
            try (Stream<Path> paths = Files.walk(sourceRoot)) {
                for (Path path : paths.filter(this::isJavaSource).toList()) {
                    long lineCount;
                    try (Stream<String> lines = Files.lines(path)) {
                        lineCount = lines.count();
                    }
                    if (lineCount > MAX_PRODUCTION_SOURCE_LINES
                            && !ALLOWED_OVERSIZED_SOURCES.contains(normalize(root.relativize(path)))) {
                        oversizedSources.add(normalize(root.relativize(path)) + " lines=" + lineCount);
                    }
                }
            }
        }

        assertTrue(
                oversizedSources.isEmpty(),
                () -> "生产 Java 源码超过 1200 行，请按职责拆分：\n" + String.join("\n", oversizedSources)
        );
    }

    private Set<String> scanBusinessViolations() throws IOException {
        Path root = findBackendRoot();
        Set<String> violations = new HashSet<>();
        for (String module : MODULES) {
            Path sourceRoot = root.resolve(module).resolve("src/main/java");
            if (!Files.isDirectory(sourceRoot)) {
                continue;
            }
            try (Stream<Path> paths = Files.walk(sourceRoot)) {
                for (Path path : paths.filter(this::isJavaSource).toList()) {
                    inspectSource(root, module, path, Files.readString(path), violations);
                }
            }
        }
        return violations;
    }

    private Map<String, Set<String>> scanFeatureDependencies() throws IOException {
        Path root = findBackendRoot();
        Map<String, Set<String>> graph = new HashMap<>();
        for (String module : MODULES) {
            Path sourceRoot = root.resolve(module).resolve("src/main/java");
            if (!Files.isDirectory(sourceRoot)) {
                continue;
            }
            try (Stream<Path> paths = Files.walk(sourceRoot)) {
                for (Path path : paths.filter(this::isJavaSource).toList()) {
                    String relativePath = normalize(root.relativize(path));
                    String sourceFeature = extractSourceFeature(relativePath);
                    if (sourceFeature == null) {
                        continue;
                    }
                    Matcher matcher = FEATURE_IMPORT_PATTERN.matcher(Files.readString(path));
                    while (matcher.find()) {
                        String targetFeature = matcher.group(1);
                        if (!sourceFeature.equals(targetFeature)) {
                            graph.computeIfAbsent(sourceFeature, ignored -> new HashSet<>()).add(targetFeature);
                        }
                    }
                }
            }
        }
        return graph;
    }

    private boolean hasDependencyPath(
            Map<String, Set<String>> graph,
            String current,
            String target,
            Set<String> visited
    ) {
        if (current.equals(target)) {
            return true;
        }
        if (!visited.add(current)) {
            return false;
        }
        for (String next : graph.getOrDefault(current, Set.of())) {
            if (hasDependencyPath(graph, next, target, visited)) {
                return true;
            }
        }
        return false;
    }

    private Set<String> loadAllowedViolations() throws IOException {
        Path allowlist = findBackendRoot()
                .resolve("omninest-app/src/test/resources/architecture/backend-dependency-allowlist.txt");
        Set<String> allowed = new HashSet<>();
        for (String line : Files.readAllLines(allowlist)) {
            String trimmed = line.trim();
            if (trimmed.isEmpty() || trimmed.startsWith("#")) {
                continue;
            }
            allowed.add(trimmed);
        }
        return allowed;
    }

    private void inspectSource(
            Path root,
            String module,
            Path path,
            String content,
            Set<String> violations
    ) {
        String relativePath = normalize(root.relativize(path));
        String sourceFeature = extractSourceFeature(relativePath);
        Matcher repositoryMatcher = REPOSITORY_IMPORT_PATTERN.matcher(content);
        while (repositoryMatcher.find()) {
            String targetFeature = repositoryMatcher.group(1);
            String importedType = repositoryMatcher.group(2);
            String importedPackage = "com.omninest.modules." + targetFeature + ".repository." + importedType;
            if (sourceFeature != null && !sourceFeature.equals(targetFeature)) {
                violations.add("CROSS_MODULE_REPOSITORY " + relativePath + " -> " + importedPackage);
            }
            if (relativePath.contains("/controller/")) {
                violations.add("CONTROLLER_REPOSITORY " + relativePath + " -> " + importedPackage);
            }
            if (module.equals("omninest-worker") && relativePath.endsWith("Consumer.java")) {
                violations.add("WORKER_CONSUMER_REPOSITORY " + relativePath + " -> " + importedPackage);
            }
        }

        if (sourceFeature != null && relativePath.contains("/controller/")) {
            Matcher serviceMatcher = SERVICE_IMPORT_PATTERN.matcher(content);
            while (serviceMatcher.find()) {
                String targetFeature = serviceMatcher.group(1);
                if (!sourceFeature.equals(targetFeature)) {
                    violations.add("CONTROLLER_CROSS_MODULE_SERVICE " + relativePath
                            + " -> com.omninest.modules." + targetFeature + ".service."
                            + serviceMatcher.group(2));
                }
            }
        }

        if (module.equals("omninest-worker") && relativePath.endsWith("Consumer.java")) {
            long lineCount = content.lines().count();
            if (lineCount > MAX_WORKER_CONSUMER_SOURCE_LINES
                    && !ALLOWED_OVERSIZED_SOURCES.contains(relativePath)) {
                violations.add("WORKER_CONSUMER_SIZE " + relativePath + " lines=" + lineCount);
            }
            if (content.contains("@Transactional")) {
                violations.add("WORKER_CONSUMER_TRANSACTION " + relativePath);
            }
            Matcher infrastructureMatcher = WORKER_CONSUMER_INFRASTRUCTURE_IMPORT_PATTERN.matcher(content);
            while (infrastructureMatcher.find()) {
                violations.add("WORKER_CONSUMER_INFRASTRUCTURE " + relativePath
                        + " -> " + infrastructureMatcher.group(1));
            }
        }

        if (module.equals("omninest-common") || module.equals("omninest-infrastructure")) {
            Matcher businessMatcher = BUSINESS_IMPORT_PATTERN.matcher(content);
            while (businessMatcher.find()) {
                violations.add("SHARED_MODULE_BUSINESS " + relativePath + " -> " + businessMatcher.group(1));
            }
        }

        if (module.equals("omninest-system")) {
            Matcher businessMatcher = BUSINESS_IMPORT_PATTERN.matcher(content);
            while (businessMatcher.find()) {
                String importedType = businessMatcher.group(1);
                if (importedType.startsWith("com.omninest.modules.file.")) {
                    violations.add("SYSTEM_FILE_REVERSE_DEPENDENCY " + relativePath + " -> " + importedType);
                }
            }
        }

        if (module.equals("omninest-common")) {
            Matcher infrastructureMatcher = COMMON_FORBIDDEN_IMPORT_PATTERN.matcher(content);
            while (infrastructureMatcher.find()) {
                violations.add("COMMON_INFRASTRUCTURE " + relativePath + " -> "
                        + infrastructureMatcher.group());
            }
        }

        if (isBusinessModule(module) && MINIO_PROPERTIES_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_MINIO_CONFIGURATION " + relativePath
                    + " -> com.omninest.common.config.MinioProperties");
        }

        if (isBusinessModule(module) && REDIS_TOKEN_BUCKET_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_REDIS_TOKEN_BUCKET " + relativePath
                    + " -> com.omninest.common.ratelimit.RedisTokenBucketRateLimiter");
        }

        if ("file".equals(sourceFeature) && REDIS_UTIL_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("FILE_REDIS_UTIL " + relativePath + " -> com.omninest.common.util.RedisUtil");
        }

        if (module.equals("omninest-system") && REDIS_UTIL_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("SYSTEM_REDIS_UTIL " + relativePath + " -> com.omninest.common.util.RedisUtil");
        }

        if (module.equals("omninest-media")
                && REDIS_UTIL_IMPORT_PATTERN.matcher(content).find()
                && !relativePath.contains("/infrastructure/")) {
            violations.add("MEDIA_REDIS_UTIL_OUTSIDE_INFRASTRUCTURE " + relativePath
                    + " -> com.omninest.common.util.RedisUtil");
        }

        if (isBusinessModule(module) && SSRF_VALIDATOR_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_SSRF_VALIDATOR " + relativePath
                    + " -> com.omninest.common.security.SsrfSafeUrlValidator");
        }

        if (isBusinessModule(module) && UPLOAD_PROPERTIES_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_UPLOAD_CONFIGURATION " + relativePath
                    + " -> com.omninest.common.config.UploadProperties");
        }

        if (isBusinessModule(module) && RCLONE_PROPERTIES_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_RCLONE_CONFIGURATION " + relativePath
                    + " -> com.omninest.common.config.RcloneProperties");
        }

        if (isBusinessModule(module) && RCLONE_CLIENT_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_RCLONE_CLIENT " + relativePath
                    + " -> com.omninest.common.rclone.RcloneRcClient");
        }

        Matcher offlineDownloadMatcher = OFFLINE_DOWNLOAD_INFRASTRUCTURE_IMPORT_PATTERN.matcher(content);
        if (isBusinessModule(module) && offlineDownloadMatcher.find()) {
            violations.add("BUSINESS_OFFLINE_DOWNLOAD_INFRASTRUCTURE " + relativePath
                    + " -> " + offlineDownloadMatcher.group(1));
        }

        if (isBusinessModule(module) && CREDENTIAL_CIPHER_IMPLEMENTATION_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_CREDENTIAL_CIPHER_IMPLEMENTATION " + relativePath
                    + " -> com.omninest.common.security.AesGcmCredentialCipher");
        }

        Matcher redisSessionMatcher = REDIS_SESSION_IMPLEMENTATION_IMPORT_PATTERN.matcher(content);
        if (isBusinessModule(module) && redisSessionMatcher.find()) {
            violations.add("BUSINESS_REDIS_SESSION_IMPLEMENTATION " + relativePath
                    + " -> " + redisSessionMatcher.group(1));
        }

        if (isBusinessModule(module) && REDIS_RUNTIME_CONFIG_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_REDIS_RUNTIME_CONFIG " + relativePath
                    + " -> com.omninest.common.config.RedisRuntimeConfigCache");
        }

        if (isBusinessModule(module) && AI_SIDECAR_CLIENT_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_AI_SIDECAR_CLIENT " + relativePath
                    + " -> com.omninest.common.ai.AiSidecarClient");
        }

        if (isBusinessModule(module) && SECURITY_PROPERTIES_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_SECURITY_PROPERTIES " + relativePath
                    + " -> com.omninest.common.config.SecurityProperties");
        }

        if (isBusinessModule(module) && HMAC_AUTHENTICATOR_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_HMAC_AUTHENTICATOR " + relativePath
                    + " -> com.omninest.common.security.HmacSha256PayloadAuthenticator");
        }

        if (isBusinessModule(module) && JWT_AUTHORITY_CONVERTER_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("BUSINESS_JWT_AUTHORITY_CONVERTER " + relativePath
                    + " -> com.omninest.common.security.JwtAuthorityConverter");
        }

        if ("weather".equals(sourceFeature)
                && WEATHER_CONFIG_CENTER_SERVICE_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("WEATHER_CONFIG_CENTER_IMPLEMENTATION " + relativePath
                    + " -> com.omninest.modules.configcenter.service.ConfigCenterService");
        }

        if ("notification".equals(sourceFeature)
                && USER_PREFERENCE_SERVICE_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("NOTIFICATION_PREFERENCE_IMPLEMENTATION " + relativePath
                    + " -> com.omninest.modules.preferences.service.UserPreferenceService");
        }

        if (!"notification".equals(sourceFeature)
                && NOTIFICATION_SERVICE_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("CROSS_FEATURE_NOTIFICATION_IMPLEMENTATION " + relativePath
                    + " -> com.omninest.modules.notification.service.NotificationService");
        }

        if ("music".equals(sourceFeature) && VIDEO_SERVICE_IMPORT_PATTERN.matcher(content).find()) {
            violations.add("MUSIC_VIDEO_SERVICE_DEPENDENCY " + relativePath);
        }

        if ("reader".equals(sourceFeature) || "music".equals(sourceFeature)) {
            Matcher objectStorageMatcher = OBJECT_STORAGE_PRIMITIVE_IMPORT_PATTERN.matcher(content);
            while (objectStorageMatcher.find()) {
                violations.add("MEDIA_BYPASSES_FILE_CONTENT_ACCESS " + relativePath
                        + " -> com.omninest.common.storage." + objectStorageMatcher.group(1));
            }
        }
    }

    private boolean isBusinessModule(String module) {
        return module.equals("omninest-system")
                || module.equals("omninest-file")
                || module.equals("omninest-media")
                || module.equals("omninest-worker");
    }

    private boolean isJavaSource(Path path) {
        return Files.isRegularFile(path) && path.getFileName().toString().endsWith(".java");
    }

    private String extractSourceFeature(String path) {
        Matcher matcher = SOURCE_FEATURE_PATTERN.matcher("/" + path);
        return matcher.find() ? matcher.group(1) : null;
    }

    private String normalize(Path path) {
        return path.toString().replace('\\', '/');
    }

    private Path findBackendRoot() {
        Path current = Path.of("").toAbsolutePath();
        while (current != null) {
            if (Files.isDirectory(current.resolve("omninest-app"))
                    && Files.isDirectory(current.resolve("omninest-common"))) {
                return current;
            }
            current = current.getParent();
        }
        throw new IllegalStateException("无法定位后端仓库根目录");
    }
}
