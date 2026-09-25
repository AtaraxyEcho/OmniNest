package com.omninest.modules.file.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 共享空间权限实体，按角色控制共享空间操作权限。
 */
@Entity
@Table(name = "shared_space_permissions", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class SharedSpacePermission {

    /**
     * 共享空间操作类型枚举。
     */
    public enum Action {
        CAN_BROWSE,
        CAN_UPLOAD,
        CAN_DOWNLOAD,
        CAN_DELETE_OWN,
        CAN_DELETE_ANY,
        CAN_MOVE_TO,
        CAN_MOVE_FROM,
        CAN_CREATE_FOLDER
    }

    /**
     * 检查是否允许指定操作。
     */
    public boolean isAllowed(Action action) {
        return switch (action) {
            case CAN_BROWSE -> canBrowse;
            case CAN_UPLOAD -> canUpload;
            case CAN_DOWNLOAD -> canDownload;
            case CAN_DELETE_OWN -> canDeleteOwn;
            case CAN_DELETE_ANY -> canDeleteAny;
            case CAN_MOVE_TO -> canMoveTo;
            case CAN_MOVE_FROM -> canMoveFrom;
            case CAN_CREATE_FOLDER -> canCreateFolder;
        };
    }

    @Id
    private UUID id;

    @Column(name = "role_id", nullable = false, unique = true)
    private UUID roleId;

    @Column(name = "can_browse", nullable = false)
    private boolean canBrowse = true;

    @Column(name = "can_upload", nullable = false)
    private boolean canUpload = true;

    @Column(name = "can_download", nullable = false)
    private boolean canDownload = true;

    @Column(name = "can_delete_own", nullable = false)
    private boolean canDeleteOwn = true;

    @Column(name = "can_delete_any", nullable = false)
    private boolean canDeleteAny = false;

    @Column(name = "can_move_to", nullable = false)
    private boolean canMoveTo = true;

    @Column(name = "can_move_from", nullable = false)
    private boolean canMoveFrom = true;

    @Column(name = "can_create_folder", nullable = false)
    private boolean canCreateFolder = true;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    @Column(name = "version", nullable = false)
    private Integer version = 0;

    @PrePersist
    void fillCreatedFields() {
        if (id == null) {
            id = UUID.randomUUID();
        }
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        if (updatedAt == null) {
            updatedAt = now;
        }
    }

    @PreUpdate
    void fillUpdatedAt() {
        updatedAt = Instant.now();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) {
            return true;
        }
        if (!(o instanceof SharedSpacePermission other)) {
            return false;
        }
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }

    @Override
    public String toString() {
        return "SharedSpacePermission{id=" + id + ", roleId=" + roleId
                + ", canBrowse=" + canBrowse + ", canUpload=" + canUpload
                + ", canDownload=" + canDownload + ", canDeleteOwn=" + canDeleteOwn
                + ", canDeleteAny=" + canDeleteAny + ", canMoveTo=" + canMoveTo
                + ", canMoveFrom=" + canMoveFrom + ", canCreateFolder=" + canCreateFolder + "}";
    }
}
