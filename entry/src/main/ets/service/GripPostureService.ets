/**
 * 智感握姿服务
 *
 * 基于 HarmonyOS 多模态感知（@kit.MultimodalAwarenessKit 的 motion 能力），
 * 实时监测用户握持手机的手势（左手 / 右手 / 双手 / 未握持），
 * 供 UI 将悬浮按钮等元素移动到拇指可达侧，提升单手操作体验。
 *
 * 说明：
 * - 需 API 20+ 且设备支持（设置-系统存在「智感握姿」开关）；不支持时订阅会抛 801，
 *   此处做降级处理——保持默认右手握姿，不影响功能。
 * - 采用观察者模式：多个页面共享同一份订阅，首个监听者触发 motion.on，
 *   末个监听者移除时触发 motion.off，避免重复订阅与内存泄漏。
 * - 需在 module.json5 声明 ohos.permission.DETECT_GESTURE / ohos.permission.ACTIVITY_MOTION。
 */

import { motion } from '@kit.MultimodalAwarenessKit';
import { BusinessError } from '@kit.BasicServicesKit';

export type GripListener = (status: motion.HoldingHandStatus) => void;

export class GripPostureService {
  private static instance: GripPostureService;
  private listeners: GripListener[] = [];
  private subscribed: boolean = false;
  // 默认右手握持：多数用户惯用右手，且与按钮默认右下角位置一致
  private currentStatus: motion.HoldingHandStatus = motion.HoldingHandStatus.RIGHT_HAND_HELD;

  private constructor() {}

  static getInstance(): GripPostureService {
    if (!GripPostureService.instance) {
      GripPostureService.instance = new GripPostureService();
    }
    return GripPostureService.instance;
  }

  /** 当前握姿（同步读取，订阅前即可用作初值） */
  getStatus(): motion.HoldingHandStatus {
    return this.currentStatus;
  }

  /** 添加监听并按需开启订阅；返回当前握姿便于初始化 UI */
  addListener(listener: GripListener): motion.HoldingHandStatus {
    this.listeners.push(listener);
    this.ensureSubscribed();
    return this.currentStatus;
  }

  /** 移除监听；无监听者时关闭订阅 */
  removeListener(listener: GripListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
    if (this.listeners.length === 0) {
      this.unsubscribe();
    }
  }

  private ensureSubscribed(): void {
    if (this.subscribed) {
      return;
    }
    try {
      motion.on('holdingHandChanged', this.onChanged);
      this.subscribed = true;
    } catch (err) {
      const e = err as BusinessError;
      // 801：当前设备不支持智感握姿，降级为默认右手
      console.info(`智感握姿不可用（已降级）: ${e.code}, ${e.message}`);
    }
  }

  private unsubscribe(): void {
    if (!this.subscribed) {
      return;
    }
    try {
      motion.off('holdingHandChanged', this.onChanged);
    } catch (err) {
      const e = err as BusinessError;
      console.info(`取消智感握姿订阅失败: ${e.code}, ${e.message}`);
    }
    this.subscribed = false;
  }

  // 用箭头函数保证 this 绑定，且 on/off 引用一致
  private onChanged = (status: motion.HoldingHandStatus): void => {
    this.currentStatus = status;
    for (const l of this.listeners) {
      l(status);
    }
  };

  /**
   * 将握姿映射为水平对齐：左手贴左、右手/双手/未识别贴右。
   * 用于悬浮按钮在 Stack 内左下/右下切换。
   */
  static toHorizontalAlign(status: motion.HoldingHandStatus): HorizontalAlign {
    if (status === motion.HoldingHandStatus.LEFT_HAND_HELD) {
      return HorizontalAlign.Start;
    }
    return HorizontalAlign.End;
  }
}
