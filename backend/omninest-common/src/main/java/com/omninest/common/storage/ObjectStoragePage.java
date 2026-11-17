package com.omninest.common.storage;

import java.util.List;

/**
 * 对象存储分页清单。
 *
 * @param objects 当前页对象摘要
 * @param nextContinuationToken 下一页续查标识，完成扫描时为 null
 * @author OmniNest
 */
public record ObjectStoragePage(
        List<ObjectStorageObject> objects,
        String nextContinuationToken
) {
    public ObjectStoragePage {
        objects = objects == null ? List.of() : List.copyOf(objects);
        if (nextContinuationToken != null && nextContinuationToken.isBlank()) {
            nextContinuationToken = null;
        }
    }

    /**
     * 判断是否存在下一页。
     *
     * @return 存在下一页时返回 true
     */
    public boolean hasNext() {
        return nextContinuationToken != null;
    }
}
