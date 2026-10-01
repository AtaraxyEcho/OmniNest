package com.omninest.common.config;

import org.springframework.cache.annotation.EnableCaching;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.serializer.StringRedisSerializer;

/**
 * Redis 模板配置，统一使用字符串 Key 与字符串 Value。
 *
 * <p>历史版本使用 fastjson2 GenericFastJsonRedisSerializer 作为值序列化器，
 * 该集成类默认启用 AutoType（读取时按 {@code @type} 实例化类）；直连该模板的消费方
 * （配置缓存、运行时注册表、限流 Lua 参数）实际只读写字符串与数值，不依赖多态类型信息，
 * 因此改为纯字符串序列化，彻底移除反序列化攻击面。业务 JSON 由调用方自行序列化。
 */
@Configuration
public class RedisConfig {

    @Bean
    public RedisTemplate<Object, Object> redisTemplate(RedisConnectionFactory connectionFactory) {
        RedisTemplate<Object, Object> template = new RedisTemplate<>();
        StringRedisSerializer stringSerializer = new StringRedisSerializer();

        template.setConnectionFactory(connectionFactory);
        template.setKeySerializer(stringSerializer);
        template.setValueSerializer(stringSerializer);
        template.setHashKeySerializer(stringSerializer);
        template.setHashValueSerializer(stringSerializer);
        template.afterPropertiesSet();
        return template;
    }

    @Bean
    public StringRedisTemplate stringRedisTemplate(RedisConnectionFactory connectionFactory) {
        return new StringRedisTemplate(connectionFactory);
    }
}
