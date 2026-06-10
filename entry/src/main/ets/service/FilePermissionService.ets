/**
 * 文件持久化授权服务
 *
 * 鸿蒙系统出于安全考虑，DocumentViewPicker 选中文件默认只授予临时权限，
 * App 重启后即失效。要长期访问/回写某个文件，需使用 fileShare 接口：
 *   1. 导入时 persistPermission：持久化该 URI 的读写权限；
 *   2. 每次启动访问前 activatePermission：激活已持久化的权限；
 *   3. 从列表移除时 revokePermission：回收权限。
 *
 * 需在 module.json5 声明 ohos.permission.FILE_ACCESS_PERSIST。
 * 参考：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/file-persistpermission
 *
 * 注：以上接口在部分设备/模拟器上可能不可用，故全部做降级处理——
 * 授权失败不阻断流程，至少保证本次会话内可正常读写。
 */

import { fileShare } from '@kit.CoreFileKit';

export class FilePermissionService {
  private static instance: FilePermissionService;

  private constructor() {}

  static getInstance(): FilePermissionService {
    if (!FilePermissionService.instance) {
      FilePermissionService.instance = new FilePermissionService();
    }
    return FilePermissionService.instance;
  }

  /** 读写模式：READ_MODE | WRITE_MODE */
  private buildPolicies(uris: string[]): Array<fileShare.PolicyInfo> {
    const mode: number = fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE;
    return uris.map((uri): fileShare.PolicyInfo => {
      return { uri: uri, operationMode: mode };
    });
  }

  /** 导入时持久化授权（失败仅记录，不抛出） */
  async persist(uris: string[]): Promise<void> {
    if (uris.length === 0) {
      return;
    }
    try {
      await fileShare.persistPermission(this.buildPolicies(uris));
    } catch (e) {
      console.error('持久化文件权限失败（将仅在本次会话内有效）:', JSON.stringify(e));
    }
  }

  /** 访问前激活已持久化的授权（失败仅记录，不抛出） */
  async activate(uris: string[]): Promise<void> {
    if (uris.length === 0) {
      return;
    }
    try {
      await fileShare.activatePermission(this.buildPolicies(uris));
    } catch (e) {
      console.error('激活文件权限失败（可能尚未持久化或系统不支持）:', JSON.stringify(e));
    }
  }

  /** 移除文件时回收授权（失败仅记录，不抛出） */
  async revoke(uri: string): Promise<void> {
    try {
      await fileShare.revokePermission(this.buildPolicies([uri]));
    } catch (e) {
      console.error('回收文件权限失败:', JSON.stringify(e));
    }
  }
}
