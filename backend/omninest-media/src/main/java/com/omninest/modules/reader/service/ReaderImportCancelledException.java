package com.omninest.modules.reader.service;

/**
 * 阅读解析任务收到用户取消信号后使用的内部协作式中断异常。
 */
final class ReaderImportCancelledException extends RuntimeException {
    ReaderImportCancelledException() {
        super("阅读导入已取消");
    }
}
