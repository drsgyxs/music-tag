/**
 * 沉浸光感（材质）适配常量与降级开关
 *
 * HarmonyOS 6（API 23+）提供系统级「沉浸光感」材质：通用属性 backgroundMaterial(MaterialStyle)，
 * 配合透明底色，可让标题栏 / 按钮等呈现真实的光影浮起与层次感。
 *
 * 材质密度：
 * - MaterialStyle.THIN    轻薄：按钮、卡片
 * - MaterialStyle.REGULAR 常规：导航栏、底栏
 * - MaterialStyle.THICK   厚重：侧边栏、弹窗
 *
 * 本项目 compatibleSdkVersion = 6.1.1(24) > API 23，目标设备均支持该材质能力，
 * 故默认开启。各组件仍提供纯色回退分支：若需在不支持的环境调试，
 * 将 LUMINANCE_SUPPORTED 置为 false 即回退到原纯色背景，避免「透明底无材质」导致元素不可见。
 */

/** 沉浸光感总开关（目标 API 24 默认开启；调试降级时改为 false） */
export const LUMINANCE_SUPPORTED: boolean = true;

