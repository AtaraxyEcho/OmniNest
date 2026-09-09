package com.omninest.common.config;

import com.alibaba.fastjson2.JSON;
import com.omninest.common.messaging.QueueNames;
import java.lang.reflect.Type;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.amqp.core.AcknowledgeMode;
import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.FanoutExchange;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.rabbit.config.SimpleRabbitListenerContainerFactory;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.support.converter.MessageConversionException;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * RabbitMQ 交换机、队列、死信队列与消息序列化配置。
 *
 * @author OmniNest
 */
@Slf4j
@Configuration
@RequiredArgsConstructor
public class RabbitMqConfig {

    private final RabbitMessagingProperties properties;

    @Bean
    FanoutExchange configRefreshExchange() {
        return new FanoutExchange(QueueNames.CONFIG_REFRESH_EXCHANGE, true, false);
    }

    @Bean
    TopicExchange syncEventExchange() {
        return new TopicExchange(QueueNames.SYNC_EVENT_EXCHANGE, true, false);
    }

    @Bean
    TopicExchange notificationEventExchange() {
        return new TopicExchange(QueueNames.NOTIFICATION_EVENT_EXCHANGE, true, false);
    }

    @Bean
    DirectExchange taskExchange() {
        return new DirectExchange(QueueNames.TASK_EXCHANGE, true, false);
    }

    @Bean
    DirectExchange deadLetterExchange() {
        return new DirectExchange(QueueNames.DEAD_LETTER_EXCHANGE, true, false);
    }

    @Bean
    Queue configRefreshQueue() {
        return QueueBuilder.nonDurable()
                .exclusive()
                .autoDelete()
                .build();
    }

    @Bean
    Binding configRefreshBinding(Queue configRefreshQueue, FanoutExchange configRefreshExchange) {
        return BindingBuilder.bind(configRefreshQueue).to(configRefreshExchange);
    }

    @Bean
    Queue fileIndexQueue() {
        return durableQueue(QueueNames.FILE_INDEX_QUEUE);
    }

    @Bean
    Queue fileRestoreIndexQueue() {
        return durableQueue(QueueNames.FILE_RESTORE_INDEX_QUEUE);
    }

    @Bean
    Queue mediaAutoImportQueue() {
        return durableQueue(QueueNames.MEDIA_AUTO_IMPORT_QUEUE);
    }

    @Bean
    Queue textExtractionQueue() {
        return durableQueue(QueueNames.TEXT_EXTRACTION_QUEUE);
    }

    @Bean
    Queue mediaQueue() {
        return durableQueue(QueueNames.MEDIA_QUEUE);
    }

    @Bean
    Queue offlineDownloadQueue() {
        return durableQueue(QueueNames.OFFLINE_DOWNLOAD_QUEUE);
    }

    @Bean
    Queue videoTranscodeQueue() {
        return durableQueue(QueueNames.VIDEO_TRANSCODE_QUEUE);
    }

    @Bean
    Queue localVideoLibraryScanQueue() {
        return durableQueue(QueueNames.LOCAL_VIDEO_LIBRARY_SCAN_QUEUE);
    }

    @Bean
    Queue localVideoLibraryApplyQueue() {
        return durableQueue(QueueNames.LOCAL_VIDEO_LIBRARY_APPLY_QUEUE);
    }

    @Bean
    Queue externalImportQueue() {
        return durableQueue(QueueNames.EXTERNAL_IMPORT_QUEUE);
    }

    @Bean
    Queue musicScanQueue() {
        return durableQueue(QueueNames.MUSIC_SCAN_QUEUE);
    }

    @Bean
    Queue musicScrapeQueue() {
        return durableQueue(QueueNames.MUSIC_SCRAPE_QUEUE);
    }

    @Bean
    Queue thumbnailQueue() {
        return durableQueue(QueueNames.THUMBNAIL_QUEUE);
    }

    @Bean
    Queue photoScanQueue() {
        return durableQueue(QueueNames.PHOTO_SCAN_QUEUE);
    }

    @Bean
    Queue photoThumbnailsQueue() {
        return durableQueue(QueueNames.PHOTO_THUMBNAILS_QUEUE);
    }

    @Bean
    Queue photoIndexQueue() {
        return durableQueue(QueueNames.PHOTO_INDEX_QUEUE);
    }

    @Bean
    Queue photoBatchQueue() {
        return durableQueue(QueueNames.PHOTO_BATCH_QUEUE);
    }

    @Bean
    Queue photoAiQueue() {
        return durableQueue(QueueNames.PHOTO_AI_QUEUE);
    }

    @Bean
    Queue photoGeoImportQueue() {
        return durableQueue(QueueNames.PHOTO_GEO_IMPORT_QUEUE);
    }

    @Bean
    Queue photoGeoBackfillQueue() {
        return durableQueue(QueueNames.PHOTO_GEO_BACKFILL_QUEUE);
    }

    @Bean
    Queue photoMotionQueue() {
        return durableQueue(QueueNames.PHOTO_MOTION_QUEUE);
    }

    @Bean
    Queue photoMotionRescanQueue() {
        return durableQueue(QueueNames.PHOTO_MOTION_RESCAN_QUEUE);
    }

    @Bean
    Queue comicParseQueue() {
        return durableQueue(QueueNames.COMIC_PARSE_QUEUE);
    }

    @Bean
    Queue readerParseQueue() {
        return durableQueue(QueueNames.READER_PARSE_QUEUE);
    }

    @Bean
    Queue filePurgeQueue() {
        return durableQueue(QueueNames.FILE_PURGE_QUEUE);
    }

    @Bean
    Queue deadLetterQueue() {
        return new Queue(QueueNames.DEAD_LETTER_QUEUE, true);
    }

    @Bean
    Binding fileIndexBinding(Queue fileIndexQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(fileIndexQueue).to(taskExchange).with(QueueNames.FILE_INDEX_ROUTING_KEY);
    }

    @Bean
    Binding fileRestoreIndexBinding(Queue fileRestoreIndexQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(fileRestoreIndexQueue)
                .to(taskExchange)
                .with(QueueNames.FILE_RESTORE_INDEX_ROUTING_KEY);
    }

    @Bean
    Binding mediaAutoImportBinding(Queue mediaAutoImportQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(mediaAutoImportQueue)
                .to(taskExchange)
                .with(QueueNames.MEDIA_AUTO_IMPORT_ROUTING_KEY);
    }

    @Bean
    Binding textExtractionBinding(Queue textExtractionQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(textExtractionQueue).to(taskExchange).with(QueueNames.TEXT_EXTRACTION_ROUTING_KEY);
    }

    @Bean
    Binding mediaBinding(Queue mediaQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(mediaQueue).to(taskExchange).with(QueueNames.MEDIA_SCRAPE_ROUTING_KEY);
    }

    @Bean
    Binding offlineDownloadBinding(Queue offlineDownloadQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(offlineDownloadQueue).to(taskExchange).with(QueueNames.OFFLINE_DOWNLOAD_ROUTING_KEY);
    }

    @Bean
    Binding videoTranscodeBinding(Queue videoTranscodeQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(videoTranscodeQueue).to(taskExchange).with(QueueNames.VIDEO_TRANSCODE_ROUTING_KEY);
    }

    @Bean
    Binding localVideoLibraryScanBinding(Queue localVideoLibraryScanQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(localVideoLibraryScanQueue)
                .to(taskExchange)
                .with(QueueNames.LOCAL_VIDEO_LIBRARY_SCAN_ROUTING_KEY);
    }

    @Bean
    Binding localVideoLibraryApplyBinding(Queue localVideoLibraryApplyQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(localVideoLibraryApplyQueue)
                .to(taskExchange)
                .with(QueueNames.LOCAL_VIDEO_LIBRARY_APPLY_ROUTING_KEY);
    }

    @Bean
    Binding externalImportBinding(Queue externalImportQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(externalImportQueue).to(taskExchange).with(QueueNames.EXTERNAL_IMPORT_ROUTING_KEY);
    }

    @Bean
    Binding musicScanBinding(Queue musicScanQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(musicScanQueue).to(taskExchange).with(QueueNames.MUSIC_SCAN_ROUTING_KEY);
    }

    @Bean
    Binding musicScrapeBinding(Queue musicScrapeQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(musicScrapeQueue).to(taskExchange).with(QueueNames.MUSIC_SCRAPE_ROUTING_KEY);
    }

    @Bean
    Binding thumbnailBinding(Queue thumbnailQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(thumbnailQueue).to(taskExchange).with(QueueNames.THUMBNAIL_ROUTING_KEY);
    }

    @Bean
    Binding photoScanBinding(Queue photoScanQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(photoScanQueue).to(taskExchange).with(QueueNames.PHOTO_SCAN_ROUTING_KEY);
    }

    @Bean
    Binding photoIndexBinding(Queue photoIndexQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(photoIndexQueue).to(taskExchange).with(QueueNames.PHOTO_INDEX_ROUTING_KEY);
    }

    @Bean
    Binding photoBatchBinding(Queue photoBatchQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(photoBatchQueue).to(taskExchange).with(QueueNames.PHOTO_BATCH_ROUTING_KEY);
    }

    @Bean
    Binding photoAiBinding(Queue photoAiQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(photoAiQueue).to(taskExchange).with(QueueNames.PHOTO_AI_ROUTING_KEY);
    }

    @Bean
    Binding photoGeoImportBinding(Queue photoGeoImportQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(photoGeoImportQueue).to(taskExchange).with(QueueNames.PHOTO_GEO_IMPORT_ROUTING_KEY);
    }

    @Bean
    Binding photoGeoBackfillBinding(Queue photoGeoBackfillQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(photoGeoBackfillQueue).to(taskExchange).with(QueueNames.PHOTO_GEO_BACKFILL_ROUTING_KEY);
    }

    @Bean
    Binding photoMotionBinding(Queue photoMotionQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(photoMotionQueue).to(taskExchange).with(QueueNames.PHOTO_MOTION_ROUTING_KEY);
    }

    @Bean
    Binding photoMotionRescanBinding(Queue photoMotionRescanQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(photoMotionRescanQueue).to(taskExchange).with(QueueNames.PHOTO_MOTION_RESCAN_ROUTING_KEY);
    }

    @Bean
    Binding comicParseBinding(Queue comicParseQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(comicParseQueue).to(taskExchange).with(QueueNames.COMIC_PARSE_ROUTING_KEY);
    }

    @Bean
    Binding readerParseBinding(Queue readerParseQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(readerParseQueue).to(taskExchange).with(QueueNames.READER_PARSE_ROUTING_KEY);
    }

    @Bean
    Binding filePurgeBinding(Queue filePurgeQueue, DirectExchange taskExchange) {
        return BindingBuilder.bind(filePurgeQueue).to(taskExchange).with(QueueNames.FILE_PURGE_ROUTING_KEY);
    }

    @Bean
    Binding deadLetterBinding(Queue deadLetterQueue, DirectExchange deadLetterExchange) {
        return BindingBuilder.bind(deadLetterQueue).to(deadLetterExchange).with(QueueNames.DEAD_LETTER_ROUTING_KEY);
    }

    @Bean
    public SimpleRabbitListenerContainerFactory rabbitListenerContainerFactory(
            ConnectionFactory connectionFactory,
            MessageConverter rabbitMessageConverter
    ) {
        SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(connectionFactory);
        factory.setPrefetchCount(consumerPrefetch());
        factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);
        factory.setMessageConverter(rabbitMessageConverter);
        // 监听异常与转换失败的消息直接进死信队列，避免毒消息无限 requeue 热循环。
        factory.setDefaultRequeueRejected(false);
        return factory;
    }

    @Bean
    public SimpleRabbitListenerContainerFactory transcodeListenerContainerFactory(
            ConnectionFactory connectionFactory,
            MessageConverter rabbitMessageConverter
    ) {
        SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(connectionFactory);
        factory.setPrefetchCount(1);
        factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);
        factory.setMessageConverter(rabbitMessageConverter);
        factory.setDefaultRequeueRejected(false);
        return factory;
    }

    @Bean
    public SimpleRabbitListenerContainerFactory localMediaTaskListenerContainerFactory(
            ConnectionFactory connectionFactory,
            MessageConverter rabbitMessageConverter
    ) {
        SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(connectionFactory);
        factory.setPrefetchCount(1);
        factory.setAcknowledgeMode(AcknowledgeMode.MANUAL);
        factory.setMessageConverter(rabbitMessageConverter);
        factory.setDefaultRequeueRejected(false);
        return factory;
    }

    /**
     * 创建广播事件使用的自动确认监听容器。
     *
     * @param connectionFactory RabbitMQ 连接工厂
     * @param rabbitMessageConverter 消息转换器
     * @return 自动确认监听容器工厂
     */
    @Bean
    public SimpleRabbitListenerContainerFactory broadcastListenerContainerFactory(
            ConnectionFactory connectionFactory,
            MessageConverter rabbitMessageConverter
    ) {
        SimpleRabbitListenerContainerFactory factory = new SimpleRabbitListenerContainerFactory();
        factory.setConnectionFactory(connectionFactory);
        factory.setPrefetchCount(consumerPrefetch());
        factory.setAcknowledgeMode(AcknowledgeMode.AUTO);
        factory.setMessageConverter(rabbitMessageConverter);
        return factory;
    }

    @Bean
    public MessageConverter rabbitMessageConverter() {
        return new MessageConverter() {
            @Override
            public Message toMessage(Object object, MessageProperties messageProperties)
                    throws MessageConversionException {
                byte[] body = JSON.toJSONBytes(object, StandardCharsets.UTF_8);
                validateMessageSize(body);
                messageProperties.setContentType(MessageProperties.CONTENT_TYPE_JSON);
                messageProperties.setContentEncoding(StandardCharsets.UTF_8.name());
                messageProperties.setContentLength(body.length);
                applyMessageTtl(messageProperties);
                return new Message(body, messageProperties);
            }

            @Override
            public Object fromMessage(Message message) throws MessageConversionException {
                byte[] body = message.getBody();
                if (body == null || body.length == 0) {
                    return null;
                }
                validateMessageSize(body);
                Type targetType = message.getMessageProperties().getInferredArgumentType();
                if (targetType == null || Object.class.equals(targetType)) {
                    return JSON.parse(body);
                }
                return JSON.parseObject(body, targetType);
            }
        };
    }

    @Bean
    public RabbitTemplate rabbitTemplate(
            ConnectionFactory connectionFactory,
            MessageConverter rabbitMessageConverter
    ) {
        RabbitTemplate rabbitTemplate = new RabbitTemplate(connectionFactory);
        rabbitTemplate.setMessageConverter(rabbitMessageConverter);
        rabbitTemplate.setMandatory(true);
        rabbitTemplate.setConfirmCallback((correlationData, acknowledged, cause) -> {
            if (!acknowledged) {
                log.error("RabbitMQ 发布被拒绝: correlationId={}, cause={}",
                        correlationData == null ? null : correlationData.getId(), cause);
            }
        });
        rabbitTemplate.setReturnsCallback(returned -> log.warn(
                "RabbitMQ 消息未路由: exchange={}, routingKey={}, replyCode={}, replyText={}",
                returned.getExchange(),
                returned.getRoutingKey(),
                returned.getReplyCode(),
                returned.getReplyText()
        ));
        return rabbitTemplate;
    }

    private Queue durableQueue(String queueName) {
        return QueueBuilder.durable(queueName)
                .withArgument("x-dead-letter-exchange", QueueNames.DEAD_LETTER_EXCHANGE)
                .withArgument("x-dead-letter-routing-key", QueueNames.DEAD_LETTER_ROUTING_KEY)
                .build();
    }

    private int consumerPrefetch() {
        return Math.max(1, Math.min(properties.getConsumerPrefetch(), 1000));
    }

    private void validateMessageSize(byte[] body) {
        int maximumBytes = Math.max(1, properties.getMaximumMessageBytes());
        if (body.length > maximumBytes) {
            throw new MessageConversionException("RabbitMQ 消息体超过容量限制");
        }
    }

    private void applyMessageTtl(MessageProperties messageProperties) {
        Duration messageTtl = properties.getMessageTtl();
        if (messageTtl == null || messageTtl.isZero() || messageTtl.isNegative()) {
            return;
        }
        messageProperties.setExpiration(Long.toString(messageTtl.toMillis()));
    }
}
