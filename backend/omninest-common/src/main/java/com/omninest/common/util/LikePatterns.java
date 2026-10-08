package com.omninest.common.util;

/**
 * LIKE 模式串的统一口径：用户输入的搜索词是字面量文本，不是模式。
 *
 * <p>{@code %} 与 {@code _} 在 LIKE 里是通配符，直接拼进模式会让用户的输入改变查询语义
 * （放宽成近似全库匹配）。转义只在消费方声明了转义符后才有意义：
 * JPQL 必须写 {@code like :pattern escape '\'}，与本类的反斜杠口径配套。
 * 实测：同样的转义模式，PostgreSQL 18 直接执行时按默认反斜杠转义生效，
 * 而经本项目的 Hibernate 查询未声明 {@code escape} 时匹配不到，所以消费方一律显式声明。</p>
 *
 * @author OmniNest
 */
public final class LikePatterns {

    private LikePatterns() {
    }

    /**
     * 把值里的转义符与 LIKE 通配符按字面量转义。
     *
     * @param value 已经过业务归一化（如去空白、小写）的字符串，不可为空
     * @return 可安全拼进 LIKE 模式的字面量片段
     */
    public static String escapeSpecials(String value) {
        return value
                .replace("\\", "\\\\")
                .replace("%", "\\%")
                .replace("_", "\\_");
    }
}
