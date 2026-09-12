package com.omninest.modules.user.util;

import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Arrays;
import java.util.Locale;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * RFC 6238 TOTP（时间同步一次性密码）工具，SHA-1/6 位/30 秒周期。
 *
 * <p>Base32 编解码按 RFC 4648 实现，编码不加填充；不引入外部依赖。</p>
 *
 * @author OmniNest
 */
public final class TotpUtil {

    public static final int DIGITS = 6;
    public static final int PERIOD_SECONDS = 30;
    public static final int DEFAULT_SKEW = 1;
    /** 无匹配时间步时的返回值。 */
    public static final long NO_MATCH = Long.MIN_VALUE;

    private static final char[] ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".toCharArray();
    private static final int[] REVERSE = new int[128];
    private static final int SECRET_BYTES = 20;
    private static final SecureRandom SECURE_RANDOM = new SecureRandom();

    static {
        Arrays.fill(REVERSE, -1);
        for (int i = 0; i < ALPHABET.length; i++) {
            REVERSE[ALPHABET[i]] = i;
            REVERSE[Character.toLowerCase(ALPHABET[i])] = i;
        }
    }

    private TotpUtil() {
    }

    /**
     * 生成 20 字节随机秘钥的 Base32 编码（32 字符）。
     *
     * @return Base32 秘钥
     */
    public static String generateSecret() {
        byte[] secret = new byte[SECRET_BYTES];
        SECURE_RANDOM.nextBytes(secret);
        return base32Encode(secret);
    }

    /**
     * 构造认证器扫码使用的 otpauth URI。
     *
     * @param issuer 签发者名称
     * @param account 账户名
     * @param secret Base32 秘钥
     * @return otpauth:// URI
     */
    public static String otpauthUri(String issuer, String account, String secret) {
        return "otpauth://totp/" + urlEncode(issuer + ":" + account)
                + "?secret=" + secret
                + "&issuer=" + urlEncode(issuer)
                + "&algorithm=SHA1&digits=" + DIGITS
                + "&period=" + PERIOD_SECONDS;
    }

    /**
     * 校验验证码并返回命中的时间步。
     *
     * @param secret Base32 秘钥
     * @param code 6 位数字验证码
     * @param at 校验时刻
     * @param skew 允许的时间步偏移（前后各 skew 步）
     * @param minStepExclusive 仅接受严格大于该值的时间步（防重放），无限制传 {@link Long#MIN_VALUE}
     * @return 命中的时间步（epoch 秒 / 30），未命中返回 {@link #NO_MATCH}
     */
    public static long matchingStep(String secret, String code, Instant at, int skew, long minStepExclusive) {
        if (secret == null || secret.isBlank() || code == null) {
            return NO_MATCH;
        }
        String normalized = code.trim();
        if (normalized.length() != DIGITS) {
            return NO_MATCH;
        }
        for (int i = 0; i < DIGITS; i++) {
            if (!Character.isDigit(normalized.charAt(i))) {
                return NO_MATCH;
            }
        }
        byte[] key = base32Decode(secret);
        if (key.length == 0) {
            return NO_MATCH;
        }
        long currentStep = Math.floorDiv(at.getEpochSecond(), PERIOD_SECONDS);
        for (long step = currentStep - skew; step <= currentStep + skew; step++) {
            if (step <= minStepExclusive) {
                continue;
            }
            if (MessageDigest.isEqual(
                    computeCode(key, step).getBytes(StandardCharsets.US_ASCII),
                    normalized.getBytes(StandardCharsets.US_ASCII))) {
                return step;
            }
        }
        return NO_MATCH;
    }

    /**
     * 计算指定时间步的 6 位验证码，供测试与服务端自证使用。
     *
     * @param key 秘钥字节
     * @param step 时间步
     * @return 6 位数字字符串
     */
    static String computeCode(byte[] key, long step) {
        byte[] counter = new byte[8];
        long value = step;
        for (int i = 7; i >= 0; i--) {
            counter[i] = (byte) (value & 0xFF);
            value >>>= 8;
        }
        try {
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(new SecretKeySpec(key, "HmacSHA1"));
            byte[] hash = mac.doFinal(counter);
            int offset = hash[hash.length - 1] & 0x0F;
            int binary = ((hash[offset] & 0x7F) << 24)
                    | ((hash[offset + 1] & 0xFF) << 16)
                    | ((hash[offset + 2] & 0xFF) << 8)
                    | (hash[offset + 3] & 0xFF);
            return String.format(Locale.ROOT, "%0" + DIGITS + "d", binary % 1_000_000);
        } catch (NoSuchAlgorithmException | InvalidKeyException exception) {
            throw new IllegalStateException("TOTP 计算失败", exception);
        }
    }

    /**
     * 计算指定时刻的当前验证码，供服务端测试与状态自证使用；知晓算法不降低安全性（无秘钥无法生成）。
     *
     * @param secret Base32 秘钥
     * @param at 计算时刻
     * @return 6 位数字验证码
     */
    public static String currentCode(String secret, Instant at) {
        byte[] key = base32Decode(secret);
        if (key.length == 0) {
            throw new IllegalArgumentException("非法的 Base32 秘钥");
        }
        return computeCode(key, Math.floorDiv(at.getEpochSecond(), PERIOD_SECONDS));
    }

    /**
     * RFC 4648 Base32 编码，输出无填充。
     *
     * @param bytes 原始字节
     * @return Base32 字符串
     */
    static String base32Encode(byte[] bytes) {
        StringBuilder builder = new StringBuilder((bytes.length * 8 + 4) / 5);
        int buffer = 0;
        int bits = 0;
        for (byte b : bytes) {
            buffer = (buffer << 8) | (b & 0xFF);
            bits += 8;
            while (bits >= 5) {
                builder.append(ALPHABET[(buffer >> (bits - 5)) & 0x1F]);
                bits -= 5;
            }
        }
        if (bits > 0) {
            builder.append(ALPHABET[(buffer << (5 - bits)) & 0x1F]);
        }
        return builder.toString();
    }

    /**
     * RFC 4648 Base32 解码，容忍小写、填充符与空白；非法输入返回空数组。
     *
     * @param text Base32 字符串
     * @return 原始字节
     */
    static byte[] base32Decode(String text) {
        String cleaned = text.replace("=", "").replace(" ", "").trim();
        java.io.ByteArrayOutputStream output = new java.io.ByteArrayOutputStream(Math.max(1, cleaned.length() * 5 / 8));
        int buffer = 0;
        int bits = 0;
        for (int i = 0; i < cleaned.length(); i++) {
            char c = cleaned.charAt(i);
            if (c >= REVERSE.length || REVERSE[c] < 0) {
                return new byte[0];
            }
            buffer = (buffer << 5) | REVERSE[c];
            bits += 5;
            if (bits >= 8) {
                output.write((buffer >> (bits - 8)) & 0xFF);
                bits -= 8;
            }
        }
        return output.toByteArray();
    }

    private static String urlEncode(String value) {
        // URLEncoder 按表单编码把空格编成 "+"，otpauth 路径段使用百分号编码更兼容
        return java.net.URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }
}
