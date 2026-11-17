package com.omninest.modules.file.service;

import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;

/**
 * 文件模块统一分页参数夹取。
 */
final class FilePageRequests {

    static final int MAX_SIZE = 200;
    private static final int DEFAULT_SIZE = 100;

    private FilePageRequests() {
    }

    static Pageable of(int page, int size) {
        return of(page, size, Sort.unsorted());
    }

    static Pageable of(int page, int size, Sort sort) {
        int safePage = Math.max(0, page);
        int safeSize = Math.min(Math.max(1, size <= 0 ? DEFAULT_SIZE : size), MAX_SIZE);
        return PageRequest.of(safePage, safeSize, sort);
    }
}
