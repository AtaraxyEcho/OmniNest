package com.omninest.modules.task.runtime;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;

/**
 * 在独立 Scheduler 或启用内嵌调度器的 API 实例中创建定时组件。
 *
 * <p>恢复、清理与对账任务依赖 {@code embedded-scheduler-enabled} 开关，
 * 与消费者使用的 {@code embedded-worker-enabled} 分离，避免单实例部署
 * 只开消费者时定时任务被静默关闭。</p>
 *
 * @author OmniNest
 */
@Target({ElementType.TYPE, ElementType.METHOD})
@Retention(RetentionPolicy.RUNTIME)
@Documented
@ConditionalOnExpression("'${omninest.runtime.role:api}' == 'scheduler' || "
        + "('${omninest.runtime.role:api}' == 'api' && ${omninest.runtime.embedded-scheduler-enabled:false})")
public @interface ConditionalOnSchedulerRuntime {
}
