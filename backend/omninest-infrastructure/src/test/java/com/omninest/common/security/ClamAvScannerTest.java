package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.security.ClamAvScanner.ScanResult;
import com.omninest.common.security.ClamAvScanner.Status;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Socket;
import java.net.SocketAddress;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import org.junit.jupiter.api.Test;

/**
 * ClamAV 流式扫描协议测试。
 *
 * @author OmniNest
 */
class ClamAvScannerTest {

    @Test
    void shouldSendChunkedRequestAndParseCleanResponse() {
        byte[] content = new byte[5000];
        Arrays.fill(content, (byte) 7);
        MockSocket socket = new MockSocket("stream: OK\0".getBytes(StandardCharsets.UTF_8));
        ClamAvScanner scanner = new ClamAvScanner(() -> socket);

        ScanResult result = scanner.scan(
                new ByteArrayInputStream(content),
                "localhost",
                3310,
                5000
        );

        assertThat(result.status()).isEqualTo(Status.CLEAN);
        assertThat(result.isClean()).isTrue();
        assertThat(socket.connectTimeout()).isEqualTo(5000);
        assertChunkedRequest(socket.requestBytes(), content);
    }

    @Test
    void shouldReturnInfectedResultForFoundResponse() {
        MockSocket socket = new MockSocket(
                "stream: Eicar-Signature FOUND\0".getBytes(StandardCharsets.UTF_8)
        );
        ClamAvScanner scanner = new ClamAvScanner(() -> socket);

        ScanResult result = scanner.scan(
                InputStream.nullInputStream(),
                "localhost",
                3310,
                5000
        );

        assertThat(result.status()).isEqualTo(Status.INFECTED);
        assertThat(result.message()).contains("Eicar-Signature");
    }

    @Test
    void shouldRejectResponseBeyondConfiguredLimit() {
        byte[] response = new byte[4097];
        Arrays.fill(response, (byte) 'x');
        MockSocket socket = new MockSocket(response);
        ClamAvScanner scanner = new ClamAvScanner(() -> socket);

        ScanResult result = scanner.scan(
                InputStream.nullInputStream(),
                "localhost",
                3310,
                5000
        );

        assertThat(result.status()).isEqualTo(Status.ERROR);
        assertThat(result.message()).isEqualTo("扫描服务不可用");
    }

    @Test
    void shouldReturnErrorWhenConnectionCannotBeCreated() {
        ClamAvScanner scanner = new ClamAvScanner(() -> {
            throw new IOException("connection failed");
        });

        ScanResult result = scanner.scan(
                InputStream.nullInputStream(),
                "192.0.2.1",
                3310,
                100
        );

        assertThat(result.status()).isEqualTo(Status.ERROR);
        assertThat(result.message()).isEqualTo("扫描服务不可用");
    }

    private void assertChunkedRequest(byte[] request, byte[] content) {
        byte[] command = "zINSTREAM\0".getBytes(StandardCharsets.US_ASCII);
        assertThat(Arrays.copyOfRange(request, 0, command.length)).containsExactly(command);

        ByteBuffer buffer = ByteBuffer.wrap(request, command.length, request.length - command.length)
                .order(ByteOrder.BIG_ENDIAN);
        int firstLength = buffer.getInt();
        byte[] firstChunk = new byte[firstLength];
        buffer.get(firstChunk);
        int secondLength = buffer.getInt();
        byte[] secondChunk = new byte[secondLength];
        buffer.get(secondChunk);

        assertThat(firstLength).isEqualTo(4096);
        assertThat(secondLength).isEqualTo(content.length - firstLength);
        assertThat(firstChunk).containsExactly(Arrays.copyOfRange(content, 0, firstLength));
        assertThat(secondChunk).containsExactly(Arrays.copyOfRange(content, firstLength, content.length));
        assertThat(buffer.getInt()).isZero();
        assertThat(buffer.hasRemaining()).isFalse();
    }

    /**
     * 提供可控输入输出的测试 Socket。
     *
     * @author OmniNest
     */
    private static final class MockSocket extends Socket {
        private final InputStream response;
        private final ByteArrayOutputStream request = new ByteArrayOutputStream();
        private int connectTimeout;

        private MockSocket(byte[] response) {
            this.response = new ByteArrayInputStream(response);
        }

        private byte[] requestBytes() {
            return request.toByteArray();
        }

        private int connectTimeout() {
            return connectTimeout;
        }

        @Override
        public void connect(SocketAddress endpoint, int timeout) {
            connectTimeout = timeout;
        }

        @Override
        public void setSoTimeout(int timeout) {
            // 测试 Socket 不执行系统级选项设置。
        }

        @Override
        public InputStream getInputStream() {
            return response;
        }

        @Override
        public OutputStream getOutputStream() {
            return request;
        }

        @Override
        public synchronized void close() {
            // 测试流由测试实例持有，无需关闭系统资源。
        }
    }
}
