package com.omninest.app.file;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.OmniNestApplication;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.RequestPrincipal;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.modules.file.service.FileDownloadService;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.file.service.FilePlaybackContentService;
import com.omninest.modules.file.service.FileQueryService;
import java.net.URI;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.core.AmqpAdmin;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.beans.BeansException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 内容访问能力矩阵的真库集成测试。
 *
 * <p>共享空间的浏览位与下载位是两条独立判据：浏览位只到派生预览，取原始字节必须
 * 持有 {@code CAN_DOWNLOAD}，定向分享接收人则凭接收关系取原件。这些判定横跨
 * 角色权限表、共享空间开关、分享关系表和 File 模块守卫，单测各自打桩永远能"绿"，
 * 只有把真实行喂进真实查询才验证得到矩阵本身。</p>
 *
 * @author OmniNest
 */
@SpringBootTest(
        classes = OmniNestApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "spring.rabbitmq.dynamic=false",
                "spring.rabbitmq.listener.simple.auto-startup=false",
                "spring.main.allow-bean-definition-overriding=true",
                "omninest.messaging.rabbit.backlog-monitoring-enabled=false",
                "omninest.redis.capacity.monitoring-enabled=false",
                "omninest.runtime.role=api",
                "omninest.runtime.embedded-worker-enabled=false",
                "omninest.setup.persistent-state-enabled=false",
                "file.local-media.enabled=false",
                "omninest.clamav.enabled=false",
                "omninest.search.index-path=${java.io.tmpdir}/omninest-content-capability-it"
        }
)
@ActiveProfiles("dev")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
@Import(FileContentCapabilityIT.ExternalDependencyOverrides.class)
class FileContentCapabilityIT {

    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_capability_it")
            .withUsername("omninest")
            .withPassword("omninest");

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private FileDownloadService fileDownloadService;

    @Autowired
    private FileLifecycleGuard fileLifecycleGuard;

    @Autowired
    private FilePlaybackContentService filePlaybackContentService;

    @Autowired
    private FileQueryService fileQueryService;

    @DynamicPropertySource
    static void registerDatabaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    @DisplayName("所有者取自己的个人文件不需要共享空间权限位")
    void ownerDownloadsOwnPersonalFile() {
        UUID owner = createUser("owner");
        UUID fileId = createFile(owner, "PERSONAL", "/docs/private.bin", "application/pdf");

        var url = fileDownloadService.createDownloadUrl(principalOf(owner), fileId);

        assertThat(url.downloadUrl()).isEqualTo("https://minio.local/signed");
        assertThat(fileLifecycleGuard.requireDownloadable(principalOf(owner), fileId).id())
                .isEqualTo(fileId);
    }

    @Test
    @DisplayName("共享空间浏览位可读但不能取原件：下载位是独立判据")
    void browseOnlyMemberReadsSharedFileButCannotDownloadIt() {
        UUID owner = createUser("owner");
        UUID member = createUser("member");
        assignRole(member, createSharedSpaceRole(false, true));
        UUID fileId = createFile(owner, "SHARED", "/team/report.pdf", "application/pdf");

        assertThat(fileLifecycleGuard.requireReadable(member, fileId).id()).isEqualTo(fileId);
        assertThatThrownBy(() -> fileDownloadService.createDownloadUrl(principalOf(member), fileId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.DOWNLOAD_PERMISSION_REQUIRED);
        assertThatThrownBy(() -> filePlaybackContentService.requireDownloadable(principalOf(member), fileId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.DOWNLOAD_PERMISSION_REQUIRED);
    }

    @Test
    @DisplayName("同时持有浏览位与下载位的成员可以取共享文件原件")
    void downloadCapableMemberDownloadsSharedFile() {
        UUID owner = createUser("owner");
        UUID member = createUser("member");
        assignRole(member, createSharedSpaceRole(true, true));
        UUID fileId = createFile(owner, "SHARED", "/team/shared.pdf", "application/pdf");

        var url = fileDownloadService.createDownloadUrl(principalOf(member), fileId);

        assertThat(url.downloadUrl()).isEqualTo("https://minio.local/signed");
    }

    @Test
    @DisplayName("没有共享空间权限位的成员连浏览都被拒绝")
    void memberWithoutBrowseBitIsRejected() {
        UUID owner = createUser("owner");
        UUID member = createUser("member");
        assignRole(member, createSharedSpaceRole(false, false));
        UUID fileId = createFile(owner, "SHARED", "/team/locked.pdf", "application/pdf");

        assertThatThrownBy(() -> fileLifecycleGuard.requireReadable(member, fileId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FORBIDDEN);
    }

    @Test
    @DisplayName("他人个人文件对非接收者按不存在处理，避免存在性探测")
    void personalFileOfAnotherUserIsInvisible() {
        UUID owner = createUser("owner");
        UUID stranger = createUser("stranger");
        UUID fileId = createFile(owner, "PERSONAL", "/docs/secret.bin", "application/pdf");

        assertThatThrownBy(() -> fileDownloadService.createDownloadUrl(principalOf(stranger), fileId))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FILE_NOT_FOUND);
    }

    @Test
    @DisplayName("定向分享接收人凭接收关系取个人文件原件，不需要共享空间权限位")
    void directedShareRecipientDownloadsPersonalFile() {
        UUID owner = createUser("owner");
        UUID recipient = createUser("recipient");
        UUID fileId = createFile(owner, "PERSONAL", "/docs/shared.bin", "application/pdf");
        insertDirectFileShare(owner, fileId, recipient);

        var url = fileDownloadService.createDownloadUrl(principalOf(recipient), fileId);

        assertThat(url.downloadUrl()).isEqualTo("https://minio.local/signed");
    }

    @Test
    @DisplayName("以指定身份签发派生资产地址时仍受该身份自身的访问能力约束")
    void signingAsAUserStillRequiresThatUsersAccess() {
        UUID owner = createUser("owner");
        UUID otherOwner = createUser("other-owner");
        UUID poster = createFile(owner, "PERSONAL", "/.metadata/poster.jpg", "image/jpeg");

        assertThat(fileQueryService.createDownloadUrlAs(owner, poster).downloadUrl())
                .isEqualTo("https://minio.local/signed");
        assertThatThrownBy(() -> fileQueryService.createDownloadUrlAs(otherOwner, poster))
                .isInstanceOf(BusinessException.class)
                .extracting(exception -> ((BusinessException) exception).errorCode())
                .isEqualTo(ErrorCode.FILE_NOT_FOUND);
    }

    @Test
    @DisplayName("共享目录分享的子项按链接所有者能力签发，含其他成员上传的文件")
    void shareListingSignsChildrenByTheLinkOwnersCapability() {
        UUID linkOwner = createUser("link-owner");
        UUID uploader = createUser("uploader");
        assignRole(linkOwner, createSharedSpaceRole(true, true));
        UUID ownChild = createFile(linkOwner, "SHARED", "/team/album/own.jpg", "image/jpeg");
        UUID othersChild = createFile(uploader, "SHARED", "/team/album/other.jpg", "image/jpeg");

        // 分享链接把整个目录授权给访客，子项由谁上传不影响可见性：
        // 若把"按所有者签发"收窄成"只签所有者名下节点"，这里会静默丢链接。
        var signed = fileQueryService.createDownloadUrlsAs(linkOwner, List.of(ownChild, othersChild));

        assertThat(signed).containsKeys(ownChild, othersChild);
    }

    @Test
    @DisplayName("链接所有者没有下载位时，分享列表里的子项不再签发原文件链")
    void shareListingDropsUrlsWhenLinkOwnerCannotDownload() {
        UUID linkOwner = createUser("browse-only-owner");
        UUID uploader = createUser("uploader");
        assignRole(linkOwner, createSharedSpaceRole(false, true));
        UUID othersChild = createFile(uploader, "SHARED", "/team/album/locked.jpg", "image/jpeg");

        var signed = fileQueryService.createDownloadUrlsAs(linkOwner, List.of(othersChild));

        assertThat(signed).doesNotContainKey(othersChild);
    }

    // ── 种子 ──────────────────────────────────────────────────────────────

    private RequestPrincipal principalOf(UUID userId) {
        return RequestPrincipal.credential(() -> userId);
    }

    private UUID createUser(String prefix) {
        UUID userId = UUID.randomUUID();
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.auth_users (id, username, password_hash, created_at, updated_at, version)
                VALUES (?, ?, 'x', ?, ?, 0)
                """, userId, prefix + "-" + userId, Timestamp.from(now), Timestamp.from(now));
        return userId;
    }

    private UUID createSharedSpaceRole(boolean canDownload, boolean canBrowse) {
        UUID roleId = UUID.randomUUID();
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.auth_roles
                    (id, code, name, built_in, enabled, created_at, updated_at, version)
                VALUES (?, ?, ?, false, true, ?, ?, 0)
                """, roleId, "it-" + roleId, "能力矩阵角色 " + roleId,
                Timestamp.from(now), Timestamp.from(now));
        jdbcTemplate.update("""
                INSERT INTO omni.shared_space_permissions
                    (id, role_id, can_browse, can_download, created_at, updated_at, version)
                VALUES (?, ?, ?, ?, ?, ?, 0)
                """, UUID.randomUUID(), roleId, canBrowse, canDownload,
                Timestamp.from(now), Timestamp.from(now));
        return roleId;
    }

    private void assignRole(UUID userId, UUID roleId) {
        jdbcTemplate.update("""
                INSERT INTO omni.auth_user_roles (user_id, role_id, created_at)
                VALUES (?, ?, ?)
                """, userId, roleId, Timestamp.from(Instant.now()));
    }

    private UUID createFile(UUID ownerUserId, String spaceType, String normalizedPath, String mimeType) {
        UUID objectId = UUID.randomUUID();
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.file_objects
                    (id, bucket_name, object_key, size_bytes, mime_type, created_at, updated_at, version)
                VALUES (?, 'user-files', ?, 1024, ?, ?, ?, 0)
                """, objectId, "it/" + objectId, mimeType, Timestamp.from(now), Timestamp.from(now));
        UUID nodeId = UUID.randomUUID();
        jdbcTemplate.update("""
                INSERT INTO omni.file_nodes
                    (id, owner_user_id, node_type, name, normalized_path, mime_type, size_bytes,
                     current_object_id, is_deleted, space_type, created_at, updated_at, version)
                VALUES (?, ?, 'FILE', ?, ?, ?, 1024, ?, false, ?, ?, ?, 0)
                """, nodeId, ownerUserId,
                normalizedPath.substring(normalizedPath.lastIndexOf('/') + 1),
                normalizedPath, mimeType, objectId, spaceType,
                Timestamp.from(now), Timestamp.from(now));
        return nodeId;
    }

    private void insertDirectFileShare(UUID ownerUserId, UUID fileId, UUID recipientUserId) {
        UUID shareLinkId = UUID.randomUUID();
        Instant now = Instant.now();
        jdbcTemplate.update("""
                INSERT INTO omni.share_links
                    (id, owner_user_id, resource_type, resource_id, token_hash,
                     created_at, updated_at, version)
                VALUES (?, ?, 'FILE', ?, ?, ?, ?, 0)
                """, shareLinkId, ownerUserId, fileId, "it-" + shareLinkId,
                Timestamp.from(now), Timestamp.from(now));
        jdbcTemplate.update("""
                INSERT INTO omni.file_share_recipients (id, share_link_id, recipient_user_id, created_at)
                VALUES (?, ?, ?, ?)
                """, UUID.randomUUID(), shareLinkId, recipientUserId, Timestamp.from(now));
    }

    @TestConfiguration
    static class ExternalDependencyOverrides {

        @Bean
        @Primary
        ObjectStorageClient objectStorageClient() {
            ObjectStorageClient client = mock(ObjectStorageClient.class);
            when(client.objectExists(any(ObjectStorageKey.class))).thenReturn(true);
            when(client.createDownloadUrl(any(ObjectStorageKey.class), any(Duration.class)))
                    .thenReturn(URI.create("https://minio.local/signed"));
            when(client.createDownloadUrl(
                    any(ObjectStorageKey.class), any(Duration.class), any(), any()))
                    .thenReturn(URI.create("https://minio.local/signed"));
            return client;
        }

        @Bean
        @Primary
        AmqpAdmin amqpAdmin() {
            return mock(AmqpAdmin.class);
        }

        @Bean
        static BeanPostProcessor disableRabbitListenerStartup() {
            return new BeanPostProcessor() {
                @Override
                public Object postProcessBeforeInitialization(Object bean, String beanName)
                        throws BeansException {
                    if (bean instanceof SimpleRabbitListenerContainerFactory factory) {
                        factory.setAutoStartup(false);
                    }
                    return bean;
                }
            };
        }
    }
}
