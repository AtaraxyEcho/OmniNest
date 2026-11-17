package com.omninest.common.security;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * RFC 5869 HKDF-SHA256 密钥派生。
 *
 * <p>所有从主密钥派生用途子密钥的组件都应经过本工具，避免不同用途共用同一把
 * HMAC 密钥。盐与 info 固定后派生结果跨实例、跨重启一致。</p>
 *
 * @author OmniNest
 */
public final class HkdfSha256 {

    private static final String HMAC_ALGORITHM = "HmacSHA256";
    private static final int HASH_LENGTH_BYTES = 32;
    private static final int MAX_OUTPUT_BYTES = 255 * HASH_LENGTH_BYTES;

    private HkdfSha256() {
    }

    /**
     * 以 UTF-8 用途标签派生指定长度的子密钥。
     *
     * @param ikm 主密钥材料
     * @param salt 固定盐
     * @param info 用途标签
     * @param length 输出字节数
     * @return 派生密钥
     */
    public static byte[] deriveKey(byte[] ikm, byte[] salt, String info, int length) {
        if (info == null) {
            throw new IllegalArgumentException("HKDF 用途标签不能为空");
        }
        return deriveKey(ikm, salt, info.getBytes(StandardCharsets.UTF_8), length);
    }

    /**
     * 派生指定长度的子密钥。
     *
     * @param ikm 主密钥材料
     * @param salt 固定盐
     * @param info 用途标签（UTF-8 字节）
     * @param length 输出字节数，必须处于 1..8160
     * @return 派生密钥
     */
    public static byte[] deriveKey(byte[] ikm, byte[] salt, byte[] info, int length) {
        if (ikm == null || ikm.length == 0) {
            throw new IllegalArgumentException("HKDF 主密钥不能为空");
        }
        if (salt == null || salt.length == 0) {
            throw new IllegalArgumentException("HKDF 盐不能为空");
        }
        if (length <= 0 || length > MAX_OUTPUT_BYTES) {
            throw new IllegalArgumentException("HKDF 输出长度不合法");
        }
        try {
            Mac extract = Mac.getInstance(HMAC_ALGORITHM);
            extract.init(new SecretKeySpec(salt, HMAC_ALGORITHM));
            byte[] prk = extract.doFinal(ikm);

            Mac expand = Mac.getInstance(HMAC_ALGORITHM);
            expand.init(new SecretKeySpec(prk, HMAC_ALGORITHM));
            ByteArrayOutputStream output = new ByteArrayOutputStream(length);
            byte[] block = new byte[0];
            int counter = 1;
            while (output.size() < length) {
                expand.update(block);
                expand.update(info);
                expand.update((byte) counter++);
                block = expand.doFinal();
                output.write(block, 0, Math.min(block.length, length - output.size()));
            }
            return output.toByteArray();
        } catch (NoSuchAlgorithmException | InvalidKeyException exception) {
            throw new IllegalStateException("HKDF-SHA256 派生失败", exception);
        }
    }

    /**
     * 供测试与跨组件复用的标准盐。
     *
     * @return HKDF 盐字节
     */
    public static byte[] defaultSalt() {
        return "omninest-hkdf-salt-v1".getBytes(StandardCharsets.UTF_8);
    }
}
