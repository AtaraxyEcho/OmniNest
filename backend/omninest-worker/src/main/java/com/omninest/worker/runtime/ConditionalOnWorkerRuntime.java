package com.omninest.worker.runtime;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;

/**
 * 在独立 Worker 或启用内嵌 Worker 的 API 实例中创建任务执行组件。
 *
 * @author OmniNest
 */
@Target({ElementType.TYPE, ElementType.METHOD})
@Retention(RetentionPolicy.RUNTIME)
@Documented
@ConditionalOnExpression("'${omninest.runtime.role:api}' == 'worker' || "
        + "('${omninest.runtime.role:api}' == 'api' && ${omninest.runtime.embedded-worker-enabled:false})")
public @interface ConditionalOnWorkerRuntime {
}
