package com.omninest.modules.music.service;

import java.net.InetAddress;
import java.net.UnknownHostException;
import org.springframework.stereotype.Component;

/**
 * 解析音乐播放源主机的网络地址。
 *
 * @author OmniNest
 */
@Component
public class MusicHostAddressResolver {

    /**
     * 解析主机对应的全部网络地址。
     *
     * @param host 主机名
     * @return 主机对应的网络地址
     * @throws UnknownHostException 主机无法解析时抛出
     */
    public InetAddress[] resolve(String host) throws UnknownHostException {
        return InetAddress.getAllByName(host);
    }
}
