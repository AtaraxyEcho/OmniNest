package com.omninest.modules.quota.port;

/**
 * 共享空间用量账本的对账能力，由 File 模块实现。
 *
 * <p>共享空间没有预留机制：写入侧在上传晋升时按新对象全额加计，软删除时只按节点当前字节扣减，
 * 历史版本字节与跨空间移动因此持续留下偏差。偏差只会把账本推高，共享空间会在实际还有空间时
 * 判满，所以必须像个人配额一样定期按节点与版本的真实字节重算。</p>
 *
 * @author OmniNest
 */
public interface SharedSpaceUsageReconcile {

    /**
     * 用共享空间文件节点与历史版本的实际字节重算单行账本，并在数值变化时写回。
     */
    void reconcileUsage();
}
