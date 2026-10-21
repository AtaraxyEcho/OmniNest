package com.omninest.app.notification;

import java.io.IOException;
import java.io.StringWriter;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.cert.X509Certificate;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.regex.Pattern;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x509.BasicConstraints;
import org.bouncycastle.asn1.x509.Extension;
import org.bouncycastle.asn1.x509.GeneralName;
import org.bouncycastle.asn1.x509.GeneralNames;
import org.bouncycastle.asn1.x509.KeyUsage;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;
import org.bouncycastle.openssl.jcajce.JcaPEMWriter;

/**
 * 运行期自签证书：只活在临时目录里，供 Mailpit 开 STARTTLS 用。
 *
 * <p>把测试私钥提交进仓库会与凭据管理规范冲突，因此证书在测试启动时现生成，进程退出即删除。
 * 主题备用名按实际连接主机写入，证书链校验与主机名校验才能各自独立失败。BouncyCastle 已随
 * 邮件 starter 在类路径上，不额外引依赖。</p>
 *
 * @author OmniNest
 */
final class NotificationEmailTestCertificates {

    private static final int KEY_SIZE = 2048;
    private static final Pattern IPV4 = Pattern.compile("^\\d{1,3}(\\.\\d{1,3}){3}$");

    private NotificationEmailTestCertificates() {
    }

    /**
     * 为指定连接主机生成一对象自签证书与私钥。
     *
     * @param host 客户端连接 SMTP 时使用的主机名或地址
     * @return PEM 文件位置（证书、私钥）
     */
    static CertificatePair generateLocalhostPair(String host) {
        try {
            Path directory = Files.createTempDirectory("omninest-mailpit-tls");
            KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
            generator.initialize(KEY_SIZE);
            KeyPair keyPair = generator.generateKeyPair();
            Instant now = Instant.now();
            X500Name subject = new X500Name("CN=" + host);
            JcaX509v3CertificateBuilder builder = new JcaX509v3CertificateBuilder(
                    subject,
                    BigInteger.valueOf(now.toEpochMilli()),
                    Date.from(now.minus(Duration.ofHours(1))),
                    Date.from(now.plus(Duration.ofDays(1))),
                    subject,
                    keyPair.getPublic());
            builder.addExtension(Extension.basicConstraints, true, new BasicConstraints(false));
            builder.addExtension(
                    Extension.keyUsage,
                    true,
                    new KeyUsage(KeyUsage.digitalSignature | KeyUsage.keyEncipherment));
            builder.addExtension(
                    Extension.subjectAlternativeName,
                    false,
                    new GeneralNames(alternativeNames(host)));
            BouncyCastleProvider provider = new BouncyCastleProvider();
            X509Certificate certificate = new JcaX509CertificateConverter()
                    .setProvider(provider)
                    .getCertificate(builder.build(new JcaContentSignerBuilder("SHA256WithRSA")
                            .setProvider(provider)
                            .build(keyPair.getPrivate())));
            Path certPath = directory.resolve("fullchain.pem");
            Path keyPath = directory.resolve("privkey.pem");
            writePem(certPath, certificate);
            writePem(keyPath, keyPair.getPrivate());
            certPath.toFile().deleteOnExit();
            keyPath.toFile().deleteOnExit();
            directory.toFile().deleteOnExit();
            return new CertificatePair(certPath, keyPath);
        } catch (Exception exception) {
            throw new IllegalStateException("无法生成邮件集成测试证书", exception);
        }
    }

    private static GeneralName[] alternativeNames(String host) {
        GeneralName connectHost = IPV4.matcher(host).matches()
                ? new GeneralName(GeneralName.iPAddress, host)
                : new GeneralName(GeneralName.dNSName, host);
        return new GeneralName[] {
                connectHost,
                new GeneralName(GeneralName.dNSName, "localhost"),
                new GeneralName(GeneralName.iPAddress, "127.0.0.1")
        };
    }

    private static void writePem(Path target, Object object) throws IOException {
        StringWriter buffer = new StringWriter();
        try (JcaPEMWriter pemWriter = new JcaPEMWriter(buffer)) {
            pemWriter.writeObject(object);
            pemWriter.flush();
        }
        Files.writeString(target, buffer.toString(), StandardCharsets.US_ASCII);
    }

    /**
     * 自签证书与私钥的 PEM 位置。
     *
     * @param certificate 证书文件
     * @param privateKey 私钥文件
     */
    record CertificatePair(Path certificate, Path privateKey) {
    }
}
