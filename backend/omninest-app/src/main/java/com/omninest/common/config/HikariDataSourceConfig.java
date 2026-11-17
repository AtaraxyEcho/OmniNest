package com.omninest.common.config;

import javax.sql.DataSource;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import org.springframework.boot.jdbc.autoconfigure.DataSourceProperties;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.util.StringUtils;

/**
 * 显式装配 Hikari 数据源。
 * Spring Boot 4 默认路径会在连接池启动后再绑定 spring.datasource.hikari，触发 pool sealed 失败；
 * 这里先把参数绑定到未启动的 HikariConfig，再创建连接池。
 */
@Configuration(proxyBeanMethods = false)
public class HikariDataSourceConfig {

    @Bean
    @ConfigurationProperties(prefix = "spring.datasource.hikari")
    public HikariConfig hikariConfig() {
        HikariConfig config = new HikariConfig();
        config.setPoolName("OmniNestHikariPool");
        config.setMaximumPoolSize(8);
        config.setMinimumIdle(1);
        return config;
    }

    @Bean
    @Primary
    public DataSource dataSource(DataSourceProperties dataSourceProperties, HikariConfig hikariConfig) {
        hikariConfig.setJdbcUrl(dataSourceProperties.determineUrl());
        hikariConfig.setUsername(dataSourceProperties.determineUsername());
        hikariConfig.setPassword(dataSourceProperties.determinePassword());
        String driverClassName = dataSourceProperties.determineDriverClassName();
        if (StringUtils.hasText(driverClassName)) {
            hikariConfig.setDriverClassName(driverClassName);
        }
        return new HikariDataSource(hikariConfig);
    }
}
