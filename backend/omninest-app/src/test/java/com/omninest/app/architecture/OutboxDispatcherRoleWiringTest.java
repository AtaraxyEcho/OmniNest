package com.omninest.app.architecture;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;

import com.omninest.modules.sync.config.SyncEventProperties;
import com.omninest.modules.sync.service.RabbitSyncEventPublisher;
import com.omninest.modules.sync.service.SyncOutboxDispatcher;
import com.omninest.modules.sync.service.SyncOutboxStateService;
import com.omninest.modules.task.config.TaskOutboxProperties;
import com.omninest.modules.task.service.RabbitTaskDispatchPublisher;
import com.omninest.modules.task.service.TaskDispatchService;
import com.omninest.modules.task.service.TaskOutboxDispatcher;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

/**
 * Outbox 派发器不应再绑定 api 角色。
 *
 * <p>worker 与 scheduler 自身也会写 task_dispatches / sync_events，
 * 两个派发器必须在这两个角色下同样装配。</p>
 *
 * @author OmniNest
 */
class OutboxDispatcherRoleWiringTest {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withBean(TaskDispatchService.class, () -> mock(TaskDispatchService.class))
            .withBean(RabbitTaskDispatchPublisher.class, () -> mock(RabbitTaskDispatchPublisher.class))
            .withBean(TaskOutboxProperties.class, TaskOutboxProperties::new)
            .withBean(SyncOutboxStateService.class, () -> mock(SyncOutboxStateService.class))
            .withBean(RabbitSyncEventPublisher.class, () -> mock(RabbitSyncEventPublisher.class))
            .withBean(SyncEventProperties.class, SyncEventProperties::new)
            .withUserConfiguration(TaskOutboxDispatcher.class, SyncOutboxDispatcher.class);

    @Test
    void dispatchersArePresentInWorkerAndSchedulerRoles() {
        for (String role : new String[] {"worker", "scheduler"}) {
            contextRunner
                    .withPropertyValues("omninest.runtime.role=" + role)
                    .run(context -> {
                        assertThat(context).hasNotFailed();
                        assertThat(context).hasSingleBean(TaskOutboxDispatcher.class);
                        assertThat(context).hasSingleBean(SyncOutboxDispatcher.class);
                    });
        }
    }
}
