package com.omninest.modules.backdrop.domain;

/**
 * 背景素材生命周期状态。
 *
 * <p>正常上传在请求内同步完成；PROCESSING 仅表示素材行已提交而 MinIO 对象尚未落盘的在途窗口，
 * FAILED 仅由对账任务标记对象异常的素材，二者都不允许被选为当前背景。</p>
 *
 * @author OmniNest
 */
public enum BackdropAssetStatus {
    /** 对象落盘与缩略图处理尚未完成。 */
    PROCESSING,

    /** 素材完整可用。 */
    READY,

    /** 对账任务确认对象异常，素材不可用。 */
    FAILED
}
