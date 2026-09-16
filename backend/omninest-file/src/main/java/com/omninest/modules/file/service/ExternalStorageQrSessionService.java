package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.StorageExternalAccount;
import com.omninest.modules.file.dto.QrSessionResponse;
import com.omninest.modules.file.repository.StorageExternalAccountRepository;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 网盘扫码登录会话状态机。
 *
 * <p>P3 提供会话生命周期与属主校验骨架；具体夸克/百度协议 Adapter 后续接入。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ExternalStorageQrSessionService {

    private static final Duration SESSION_TTL = Duration.ofMinutes(5);

    private final StorageExternalAccountRepository accountRepository;

    /**
     * 发起扫码会话。
     */
    @Transactional(rollbackFor = Exception.class)
    public QrSessionResponse start(UUID ownerUserId, UUID accountId) {
        StorageExternalAccount account = accountRepository.findByIdAndOwnerUserId(accountId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储账户不存在"));
        String provider = account.getProvider().toUpperCase(java.util.Locale.ROOT);
        if (!"QUARK".equals(provider) && !"BAIDU".equals(provider)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "该连接器暂不支持扫码登录");
        }
        String sessionId = UUID.randomUUID().toString().replace("-", "");
        log.info("扫码会话已创建（协议 Adapter 待接入）: sessionId={}, accountId={}", sessionId, accountId);
        return new QrSessionResponse(
                sessionId,
                "PENDING",
                "pending://" + sessionId,
                "请使用" + provider + "客户端扫码；协议适配将在后续版本接入"
        );
    }

    /**
     * 查询扫码会话状态。
     */
    @Transactional(readOnly = true)
    public QrSessionResponse status(UUID ownerUserId, UUID accountId, String sessionId) {
        accountRepository.findByIdAndOwnerUserId(accountId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "外部存储账户不存在"));
        if (sessionId == null || sessionId.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "会话 ID 不能为空");
        }
        Instant expiresAt = Instant.now().plus(SESSION_TTL);
        if (Instant.now().isAfter(expiresAt)) {
            return new QrSessionResponse(sessionId, "EXPIRED", null, "会话已过期");
        }
        return new QrSessionResponse(sessionId, "PENDING", null, "等待扫码确认");
    }
}
