package com.omninest.modules.user.port;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 角色身份查询端口。
 *
 * <p>共享空间权限矩阵按 {@code auth_roles} 的 role_id 建行，而角色表属于
 * system 模块；File 模块只通过本端口读取角色标识，不直接跨模块访问角色仓储。</p>
 *
 * @author OmniNest
 */
public interface RoleLookup {

    /**
     * 全部角色标识与编码。
     *
     * @return 角色引用列表
     */
    List<RoleRef> listAll();

    /**
     * 判断角色是否存在。
     *
     * @param roleId 角色标识
     * @return 存在返回 true
     */
    boolean existsById(UUID roleId);

    /**
     * 按标识批量取角色编码。
     *
     * @param roleIds 角色标识集合
     * @return 角色标识到编码的映射，缺失的角色不出现
     */
    Map<UUID, String> codesById(Collection<UUID> roleIds);

    /**
     * 角色引用。
     *
     * @param id 角色标识
     * @param code 角色编码
     */
    record RoleRef(UUID id, String code) {
    }
}
