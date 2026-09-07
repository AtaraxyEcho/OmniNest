package com.omninest.modules.photos.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;

/**
 * 照片分享落地页控制器。
 *
 * <p>把 /share/{token} 以服务端 forward 转发到静态分享页 share.html：
 * 浏览器地址栏保持路径形态（不含 ?token= 查询参数），页面脚本自行从
 * pathname 解析令牌调用公开接口。</p>
 *
 * @author OmniNest
 */
@Controller
public class SharePageController {

    @GetMapping("/share/{token}")
    public String sharePage(@PathVariable String token) {
        return "forward:/share.html";
    }
}
