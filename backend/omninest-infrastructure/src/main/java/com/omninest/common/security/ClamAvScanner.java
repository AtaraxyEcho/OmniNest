package com.omninest.common.security;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 通过 clamd INSTREAM 协议流式扫描文件内容。
 *
 * @author OmniNest
 */
@Slf4j
@Component
public class ClamAvScanner {
    private static final int CHUNK_SIZE = 4096;
    private static final int RESPONSE_LIMIT_BYTES = 4096;
    private static final byte[] INSTREAM_COMMAND = "zINSTREAM\0".getBytes(StandardCharsets.US_ASCII);
    private static final byte[] PING_COMMAND = "zPING\0".getBytes(StandardCharsets.US_ASCII);

    private final SocketFactory socketFactory;

    /**
     * 创建使用系统 TCP Socket 的扫描客户端。
     */
    public ClamAvScanner() {
        this(Socket::new);
    }

    ClamAvScanner(SocketFactory socketFactory) {
        this.socketFactory = socketFactory;
    }

    /**
     * 扫描输入流中的文件内容，输入流生命周期由调用方管理。
     *
     * @param content   文件内容输入流
     * @param host      clamd 地址
     * @param port      clamd 端口
     * @param timeoutMs 连接和响应读取超时，单位为毫秒
     * @return 扫描结果
     */
    public ScanResult scan(InputStream content, String host, int port, int timeoutMs) {
        try (Socket socket = socketFactory.create()) {
            socket.connect(new InetSocketAddress(host, port), timeoutMs);
            socket.setSoTimeout(timeoutMs);
            try (OutputStream output = socket.getOutputStream();
                    InputStream response = socket.getInputStream()) {
                writeScanRequest(content, output);
                return parseResponse(readResponse(response));
            }
        } catch (Exception e) {
            log.warn("ClamAV 扫描失败: host={}:{}, errorType={}",
                    host, port, e.getClass().getSimpleName());
            return ScanResult.error("扫描服务不可用");
        }
    }

    /**
     * 通过 clamd PING 命令检查服务连通性。
     *
     * @param host clamd 地址
     * @param port clamd 端口
     * @param timeoutMs 连接和读取超时毫秒数
     * @return 收到 PONG 时返回 true
     */
    public boolean ping(String host, int port, int timeoutMs) {
        try (Socket socket = socketFactory.create()) {
            socket.connect(new InetSocketAddress(host, port), timeoutMs);
            socket.setSoTimeout(timeoutMs);
            try (OutputStream output = socket.getOutputStream();
                    InputStream response = socket.getInputStream()) {
                output.write(PING_COMMAND);
                output.flush();
                return "PONG".equalsIgnoreCase(readResponse(response));
            }
        } catch (Exception exception) {
            log.debug("ClamAV 健康探针失败: host={}:{}, errorType={}",
                    host, port, exception.getClass().getSimpleName());
            return false;
        }
    }

    private void writeScanRequest(InputStream content, OutputStream output) throws IOException {
        output.write(INSTREAM_COMMAND);
        byte[] chunk = new byte[CHUNK_SIZE];
        ByteBuffer header = ByteBuffer.allocate(Integer.BYTES).order(ByteOrder.BIG_ENDIAN);
        int read;
        while ((read = content.read(chunk)) != -1) {
            if (read == 0) {
                continue;
            }
            header.clear();
            header.putInt(read);
            output.write(header.array());
            output.write(chunk, 0, read);
        }
        header.clear();
        header.putInt(0);
        output.write(header.array());
        output.flush();
    }

    private String readResponse(InputStream input) throws IOException {
        byte[] response = new byte[RESPONSE_LIMIT_BYTES];
        int length = 0;
        while (length < response.length) {
            int value = input.read();
            if (value == -1 || value == 0) {
                return new String(response, 0, length, StandardCharsets.UTF_8).trim();
            }
            response[length] = (byte) value;
            length++;
        }
        int extra = input.read();
        if (extra != -1 && extra != 0) {
            throw new IOException("ClamAV 响应超过限制");
        }
        return new String(response, StandardCharsets.UTF_8).trim();
    }

    private ScanResult parseResponse(String response) {
        if (response.endsWith(" OK")) {
            return ScanResult.clean();
        }
        if (response.endsWith(" FOUND")) {
            return ScanResult.infected(response);
        }
        if (response.isBlank()) {
            return ScanResult.error("扫描服务未返回结果");
        }
        return ScanResult.error(summarizeResponse(response));
    }

    /**
     * 扫描服务异常响应可能包含完整文件路径，进入日志前压平并截断。
     */
    private static String summarizeResponse(String response) {
        String flattened = response.replaceAll("\\s+", " ").trim();
        return flattened.length() <= 256 ? flattened : flattened.substring(0, 256) + "...";
    }

    /**
     * 扫描结果。
     *
     * @param status  扫描状态
     * @param message 结果描述
     * @author OmniNest
     */
    public record ScanResult(Status status, String message) {
        /**
         * 创建安全结果。
         *
         * @return 安全扫描结果
         */
        public static ScanResult clean() {
            return new ScanResult(Status.CLEAN, "文件安全");
        }

        /**
         * 创建感染结果。
         *
         * @param detail 病毒详情
         * @return 感染扫描结果
         */
        public static ScanResult infected(String detail) {
            return new ScanResult(Status.INFECTED, detail);
        }

        /**
         * 创建错误结果。
         *
         * @param detail 错误详情
         * @return 错误扫描结果
         */
        public static ScanResult error(String detail) {
            return new ScanResult(Status.ERROR, detail);
        }

        /**
         * 判断文件是否安全。
         *
         * @return 状态为 CLEAN 时返回 true
         */
        public boolean isClean() {
            return status == Status.CLEAN;
        }

        /**
         * 判断文件是否感染病毒。
         *
         * @return 状态为 INFECTED 时返回 true
         */
        public boolean isInfected() {
            return status == Status.INFECTED;
        }
    }

    /**
     * ClamAV 扫描状态。
     *
     * @author OmniNest
     */
    public enum Status {
        /** 文件安全。 */
        CLEAN,
        /** 文件感染病毒。 */
        INFECTED,
        /** 扫描出错。 */
        ERROR
    }

    /**
     * 创建 ClamAV TCP Socket。
     *
     * @author OmniNest
     */
    @FunctionalInterface
    interface SocketFactory {
        /**
         * 创建未连接的 Socket。
         *
         * @return 未连接的 Socket
         * @throws IOException Socket 创建失败
         */
        Socket create() throws IOException;
    }
}
