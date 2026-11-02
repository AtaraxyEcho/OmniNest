package com.omninest;

import com.omninest.common.runtime.RuntimeRole;
import java.security.Security;
import java.util.Map;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * OmniNest 单镜像应用入口，根据运行角色选择 Web 或后台进程模式。
 *
 * @author OmniNest
 */
@SpringBootApplication
@ConfigurationPropertiesScan
@EnableAsync
@EnableScheduling
public class OmniNestApplication {

    public static void main(String[] args) {
        // 必须在 InetAddress 首次加载前设置：JVM 会在此后锁定 DNS 缓存策略。
        // SSRF 校验与真正连接之间的解析间隔因此被压在 60 秒内，缩小 Rebinding 窗口。
        Security.setProperty("networkaddress.cache.ttl", "60");
        Security.setProperty("networkaddress.cache.negative.ttl", "10");
        RuntimeRole role = RuntimeRoleResolver.resolve();
        SpringApplication application = new SpringApplication(OmniNestApplication.class);
        application.setWebApplicationType(role == RuntimeRole.API
                ? WebApplicationType.SERVLET
                : WebApplicationType.NONE);
        application.setDefaultProperties(Map.of("omninest.runtime.role", role.propertyValue()));
        application.run(args);
    }

}
