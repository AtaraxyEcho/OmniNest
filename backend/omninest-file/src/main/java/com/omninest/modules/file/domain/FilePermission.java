package com.omninest.modules.file.domain;

public record FilePermission(
        boolean allowView,
        boolean allowDownload,
        boolean allowShare,
        boolean allowEdit
) {
    /** 无任何权限记录时的系统默认：全部拒绝 */
    public static FilePermission denyAll() {
        return new FilePermission(false, false, false, false);
    }

    /** 只读：允许查看，不允许下载/分享/编辑 */
    public static FilePermission readOnly() {
        return new FilePermission(true, false, false, false);
    }

    /** 完全访问权限 */
    public static FilePermission fullAccess() {
        return new FilePermission(true, true, true, true);
    }
}
