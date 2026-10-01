package com.omninest.modules.task.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

/**
 * 任务状态枚举终态与可重试契约测试。
 *
 * @author OmniNest
 */
class TaskStatusTest {

    @Test
    void discardedIsTerminalAndNotRetryable() {
        assertThat(TaskStatus.DISCARDED.isTerminal()).isTrue();
        assertThat(TaskStatus.DISCARDED.isRetryable()).isFalse();
    }

    @Test
    void cancellableStatusesAreNotTerminal() {
        assertThat(TaskStatus.QUEUED.isTerminal()).isFalse();
        assertThat(TaskStatus.RETRY_WAIT.isTerminal()).isFalse();
        assertThat(TaskStatus.RUNNING.isTerminal()).isFalse();
    }

    @Test
    void fromValueParsesDiscardedAndRejectsUnknown() {
        assertThat(TaskStatus.fromValue("discarded")).isEqualTo(TaskStatus.DISCARDED);
        assertThatThrownBy(() -> TaskStatus.fromValue("UNKNOWN_STATUS"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
