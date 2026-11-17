package com.omninest.modules.photos.service;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

/**
 * GeoNames 中文名称选优器。
 *
 * <p>打分规则：zh-Hans 基础分 4、其余 zh-* 与 zh 基础分 2，isPreferredName 加 1，
 * isHistoric 直接排除；分高者胜出，同分保留先到候选。</p>
 *
 * @author OmniNest
 */
public class GeoLocationNameSelector {

    private static final int SCORE_ZH_HANS = 4;
    private static final int SCORE_ZH_OTHER = 2;
    private static final int SCORE_PREFERRED = 1;

    private final Map<Long, Candidate> bestByGeonameId = new HashMap<>();

    private record Candidate(String name, int score) {
    }

    /**
     * 提交一条候选。
     *
     * @param geonameId GeoNames ID
     * @param language 语言代码
     * @param name 名称
     * @param preferred 是否首选名称
     * @param historic 是否历史名称
     */
    public void offer(long geonameId, String language, String name, boolean preferred, boolean historic) {
        if (name == null || name.isBlank() || historic) {
            return;
        }
        int base = score(language);
        if (base <= 0) {
            return;
        }
        int score = base + (preferred ? SCORE_PREFERRED : 0);
        Candidate existing = bestByGeonameId.get(geonameId);
        if (existing == null || score > existing.score()) {
            bestByGeonameId.put(geonameId, new Candidate(name.trim(), score));
        }
    }

    /**
     * @param geonameId GeoNames ID
     * @return 选优后的中文名，无候选时返回 null
     */
    public String best(long geonameId) {
        Candidate candidate = bestByGeonameId.get(geonameId);
        return candidate == null ? null : candidate.name();
    }

    /** @return 已收集候选的 GeoNames ID 集合 */
    public Set<Long> collectedIds() {
        return bestByGeonameId.keySet();
    }

    private int score(String language) {
        if ("zh-Hans".equals(language)) {
            return SCORE_ZH_HANS;
        }
        if ("zh".equals(language) || language.startsWith("zh-") || language.startsWith("zh_")) {
            return SCORE_ZH_OTHER;
        }
        return 0;
    }
}
