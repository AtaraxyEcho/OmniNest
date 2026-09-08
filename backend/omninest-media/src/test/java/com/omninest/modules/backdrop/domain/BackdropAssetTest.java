package com.omninest.modules.backdrop.domain;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Version;
import java.lang.reflect.Field;
import java.time.Instant;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * 以 mock 数据驱动素材实体生命周期,并锁定与 V001 基线的列契约。
 *
 * @author OmniNest
 */
class BackdropAssetTest {

    @Test
    void prePersistFillsIdentityTimestampsAndDefaultStatus() {
        BackdropAsset asset = mockAsset();

        asset.fillOnCreate();

        assertThat(asset.getId()).isNotNull();
        assertThat(asset.getCreatedAt()).isNotNull();
        assertThat(asset.getUpdatedAt()).isEqualTo(asset.getCreatedAt());
        assertThat(asset.getStatus()).isEqualTo(BackdropAssetStatus.PROCESSING);
    }

    @Test
    void prePersistKeepsExplicitStatusForReconciliationRows() {
        BackdropAsset asset = mockAsset();
        asset.setStatus(BackdropAssetStatus.FAILED);
        asset.setFailReason("object missing");

        asset.fillOnCreate();

        assertThat(asset.getStatus()).isEqualTo(BackdropAssetStatus.FAILED);
        assertThat(asset.getFailReason()).isEqualTo("object missing");
    }

    @Test
    void preUpdateRefreshesUpdatedAtOnly() {
        BackdropAsset asset = mockAsset();
        asset.fillOnCreate();
        Instant createdAt = asset.getCreatedAt();

        asset.setStatus(BackdropAssetStatus.READY);
        asset.fillOnUpdate();

        assertThat(asset.getCreatedAt()).isEqualTo(createdAt);
        assertThat(asset.getUpdatedAt()).isAfterOrEqualTo(createdAt);
    }

    @Test
    void columnContractMatchesV001Baseline() throws Exception {
        assertColumn("title", "title", false, 200);
        assertColumn("media_type", "mediaType", false, 16);
        assertColumn("file_size", "fileSize", false, null);
        assertColumn("sha256", "sha256", false, 64);
        assertColumn("status", "status", false, 16);
        assertColumn("fail_reason", "failReason", true, 200);

        assertThat(BackdropAsset.class.getDeclaredField("id").getAnnotation(Id.class)).isNotNull();
        assertThat(BackdropAsset.class.getDeclaredField("version").getAnnotation(Version.class)).isNotNull();

        Column statusColumn = columnOf("status");
        assertThat(statusColumn.nullable()).isFalse();
        assertThat(fieldOf("status").getAnnotation(Enumerated.class).value()).isEqualTo(EnumType.STRING);

        Convert convert = fieldOf("mediaType").getAnnotation(Convert.class);
        assertThat(convert).isNotNull();
        assertThat(convert.converter()).isEqualTo(BackdropMediaTypeConverter.class);
    }

    private BackdropAsset mockAsset() {
        BackdropAsset asset = new BackdropAsset();
        asset.setOwnerUserId(UUID.randomUUID());
        asset.setTitle("mock-wallpaper");
        asset.setMediaType(BackdropMediaType.IMAGE);
        asset.setFileNodeId(UUID.randomUUID());
        asset.setFileSize(1024);
        asset.setSha256("mock-sha256");
        return asset;
    }

    private void assertColumn(String name, String fieldName, boolean nullable, Integer length)
            throws NoSuchFieldException {
        Column column = columnOf(fieldName);
        assertThat(column.name()).isEqualTo(name);
        assertThat(column.nullable()).isEqualTo(nullable);
        if (length != null) {
            assertThat(column.length()).isEqualTo(length);
        }
    }

    private Column columnOf(String fieldName) throws NoSuchFieldException {
        return fieldOf(fieldName).getAnnotation(Column.class);
    }

    private Field fieldOf(String fieldName) throws NoSuchFieldException {
        Field field = BackdropAsset.class.getDeclaredField(fieldName);
        field.setAccessible(true);
        return field;
    }
}
