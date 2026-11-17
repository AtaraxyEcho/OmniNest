package com.omninest.modules.file.service;

/**
 * 文件入库的终态拒绝：重试无法改变结论（检测到威胁、摘要不一致、目标冲突等）。
 * 抛出前调用方必须已将入库记录标记为终态失败。
 *
 * @author OmniNest
 */
public class FileIngressRejectedException extends RuntimeException {

    public FileIngressRejectedException(String message) {
        super(message);
    }

    public FileIngressRejectedException(String message, Throwable cause) {
        super(message, cause);
    }
}
