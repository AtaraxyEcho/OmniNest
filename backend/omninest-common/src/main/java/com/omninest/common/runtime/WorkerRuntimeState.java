package com.omninest.common.runtime;

import java.time.Instant;
import java.util.Map;

/**
 * 描述最近一次 Worker 心跳及其可执行能力。
 *
 * @param instanceId Worker 实例标识
 * @param reportedAt 上报时间
 * @param capabilities 能力状态映射
 * @author OmniNest
 */
public record WorkerRuntimeState(
        String instanceId,
        Instant reportedAt,
        Map<String, CapabilityStatus> capabilities
) {

    public static final String PHOTO_AI_CAPABILITY = "PHOTO_AI";

    /**
     * 创建不可变 Worker 状态。
     */
    public WorkerRuntimeState {
        capabilities = capabilities == null ? Map.of() : Map.copyOf(capabilities);
    }

    /**
     * 查询指定能力，缺失时返回未知状态。
     *
     * @param capability 能力编码
     * @return 能力状态
     */
    public CapabilityStatus capability(String capability) {
        return capabilities.getOrDefault(capability, CapabilityStatus.unknown("Worker 未上报该能力"));
    }

    /**
     * 描述单项 Worker 能力状态。
     *
     * @param status 状态编码
     * @param detail 状态说明
     * @author OmniNest
     */
    public record CapabilityStatus(String status, String detail) {

        private static final String STATUS_UP = "UP";
        private static final String STATUS_DOWN = "DOWN";
        private static final String STATUS_DISABLED = "DISABLED";
        private static final String STATUS_UNKNOWN = "UNKNOWN";

        /**
         * 创建可用状态。
         *
         * @param detail 状态说明
         * @return 可用状态
         */
        public static CapabilityStatus up(String detail) {
            return new CapabilityStatus(STATUS_UP, detail);
        }

        /**
         * 创建不可用状态。
         *
         * @param detail 状态说明
         * @return 不可用状态
         */
        public static CapabilityStatus down(String detail) {
            return new CapabilityStatus(STATUS_DOWN, detail);
        }

        /**
         * 创建已禁用状态。
         *
         * @param detail 状态说明
         * @return 已禁用状态
         */
        public static CapabilityStatus disabled(String detail) {
            return new CapabilityStatus(STATUS_DISABLED, detail);
        }

        /**
         * 创建未知状态。
         *
         * @param detail 状态说明
         * @return 未知状态
         */
        public static CapabilityStatus unknown(String detail) {
            return new CapabilityStatus(STATUS_UNKNOWN, detail);
        }

        /**
         * 判断能力是否可用。
         *
         * @return 可用时返回 true
         */
        public boolean available() {
            return STATUS_UP.equals(status);
        }
    }
}
