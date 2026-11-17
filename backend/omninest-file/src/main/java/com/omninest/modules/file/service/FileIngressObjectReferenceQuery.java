package com.omninest.modules.file.service;

import java.util.Collection;
import java.util.Set;

/**
 * 查询仍在入库流程中的对象键归属。
 *
 * <p>原件桶的字节是在安全扫描通过后的晋升步骤里由服务端复制产生的，而入库记录的目标键在受理扫描
 * 时就已经登记，所以入库记录行是原件桶目标键的意图登记。对象存储孤儿审计必须把尚未走完入库流程的
 * 键排除，否则会把正在扫描或正在等待晋升的对象判成无主字节。</p>
 *
 * <p>已进入终态的入库记录不再保护目标键：晋升事务回滚时会补偿删除已复制的目标对象，但进程崩溃或
 * 补偿删除失败时不会重试，这类残留正是孤儿审计要报告的。已晋升（AVAILABLE）的记录对应对象必然已有
 * 文件对象元数据行，由元数据行保护。</p>
 *
 * @author OmniNest
 */
public interface FileIngressObjectReferenceQuery {

    /**
     * 查询候选对象键中被在途入库记录持有的键。
     *
     * @param bucketName 存储桶名称
     * @param objectKeys 候选对象键
     * @return 由在途入库记录持有的对象键
     */
    Set<String> findInFlightObjectKeys(String bucketName, Collection<String> objectKeys);
}
