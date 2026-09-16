package com.omninest.modules.file.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 实例级 OAuth 应用配置（BYOA）。
 *
 * @author OmniNest
 */
@Entity
@Table(name = "storage_connector_oauth_apps", schema = "omni")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class StorageConnectorOAuthApp {

    @Id
    private UUID id;

    @Column(name = "connector_code", nullable = false, length = 64)
    private String connectorCode;

    @Column(name = "client_id", nullable = false, length = 256)
    private String clientId;

    @Column(name = "client_secret_encrypted", nullable = false)
    private String clientSecretEncrypted;

    @Column(name = "redirect_uri", nullable = false, length = 512)
    private String redirectUri;

    @Column(nullable = false)
    private boolean enabled = true;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(nullable = false)
    private long version;

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
}
