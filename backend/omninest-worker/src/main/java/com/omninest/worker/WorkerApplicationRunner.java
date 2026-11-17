package com.omninest.worker;

import com.omninest.worker.runtime.WorkerRuntimeReporter;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * 在 Worker 角色启动完成后记录运行状态。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(prefix = "omninest.runtime", name = "role", havingValue = "worker")
public class WorkerApplicationRunner implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(WorkerApplicationRunner.class);

    private final WorkerRuntimeReporter runtimeReporter;

    @Override
    public void run(ApplicationArguments args) {
        runtimeReporter.publish();
        log.info("OmniNest worker role started");
    }
}
