package com.omninest.modules.user.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.JoinTable;
import jakarta.persistence.ManyToMany;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.time.Instant;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import com.omninest.modules.user.domain.UserStatus;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(name = "auth_users", schema = "omni")
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
public class AuthUser {
    @Id
    private UUID id;

    @Column(nullable = false, length = 80, unique = true)
    private String username;

    @Column(name = "password_hash", nullable = false, length = 255)
    private String passwordHash;

    @Column(name = "display_name", length = 120)
    private String displayName;

    @Column(length = 255)
    private String email;

    @Column(nullable = false, length = 32)
    private String status = UserStatus.ACTIVE.getValue();

    @ManyToMany(fetch = FetchType.LAZY)
    @JoinTable(
            schema = "omni",
            name = "auth_user_roles",
            joinColumns = @JoinColumn(name = "user_id"),
            inverseJoinColumns = @JoinColumn(name = "role_id")
    )
    private Set<AuthRole> roles = new HashSet<>();

    @Column(name = "quota_bytes", nullable = false)
    private long quotaBytes = 10L * 1024 * 1024 * 1024;

    @Column(name = "used_bytes", nullable = false)
    private long usedBytes;

    @Column(name = "reserved_bytes", nullable = false)
    private long reservedBytes;

    @Column(name = "avatar_file_id")
    private UUID avatarFileId;

    @Column(name = "last_login_at")
    private Instant lastLoginAt;

    /**
     * 创建时间由数据库默认值填充；实体侧只读映射，供管理列表展示与排序。
     */
    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    @Version
    @Column(nullable = false)
    private long version;

    @PrePersist
    void fillId() {
        if (id == null) {
            id = UUID.randomUUID();
        }
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof AuthUser other)) return false;
        return id != null && id.equals(other.getId());
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
