// 在引擎做任何 history 归一化之前捕获原始地址，供冷启动深链恢复使用
// （分享链接 /#/s/:token、书签、F5 刷新都必须保留进入位置）。
window.__omninestInitialHref = window.location.href;
