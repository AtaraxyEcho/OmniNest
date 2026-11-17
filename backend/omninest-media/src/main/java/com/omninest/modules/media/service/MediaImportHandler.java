package com.omninest.modules.media.service;

import com.omninest.modules.file.event.FileUploadedEvent;

/**
 * 媒体自动导入处理器。
 *
 * @author OmniNest
 */
public interface MediaImportHandler {

    /**
     * 返回模块稳定编码。
     *
     * @return 模块编码
     */
    String module();

    /**
     * 判断处理器是否支持指定文件。
     *
     * @param event 文件上传事件
     * @return 支持时返回 true
     */
    boolean supports(FileUploadedEvent event);

    /**
     * 幂等导入指定文件。
     *
     * @param event 文件上传事件
     * @return 导入结果
     */
    MediaImportResult importFile(FileUploadedEvent event);
}
