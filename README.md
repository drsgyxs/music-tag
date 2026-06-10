# 音乐标签编辑器

基于 HarmonyOS 开发的音乐标签编辑器，支持以**文件列表**方式管理导入的音频文件，并直接**读取、查看、原地写回**其元数据标签（MP3 / FLAC / M4A）。

## 功能特性

- **文件列表主页**：以列表形式管理已导入的音频文件，右下角悬浮按钮一键导入，右滑列表项可删除。
- **持久化访问**：通过 `fileShare` 持久化授权，导入的文件在 App 重启后仍可长期访问与回写（详见下文）。
- **元数据读取**：自研解析器完整读取标签，包括：
  - 标题、艺术家、专辑、专辑艺术家
  - 作曲家、词作者、发行年份、音乐类型
  - 音轨号、光盘号、版权、注释
  - 专辑封面、内嵌歌词（USLT / Vorbis / iTunes）
  - 文件信息（格式、大小、时长）
- **标签编辑与写回**：在编辑页修改标签后，点击「写入文件」将标签**原地写回原始音频文件**：
  - **MP3**：写入 ID3v2.3（UTF-16 文本帧，支持中文、封面 APIC、歌词 USLT）
  - **FLAC**：重建 VORBIS_COMMENT + PICTURE 元数据块
  - **M4A / MP4 / AAC**：重建 `moov.udta.meta.ilst`，并自动修正 `stco/co64` 块偏移
- **按格式适配字段**：不同容器对标签的支持不同，UI 会按当前文件格式启用/禁用相应字段。例如「词作者(lyricist)」在 M4A 中无标准原子，故在 M4A 下不可编辑。
- **封面管理**：查看内嵌封面，支持从相册更换封面（编码为 JPEG 写入）。
- **沉浸式 UI**：状态栏与底部导航条（小白条）透明，页面背景延伸至安全区之下。

## 标签字段支持矩阵

| 字段 | MP3 (ID3v2.3) | FLAC (Vorbis) | M4A (iTunes) |
|------|:---:|:---:|:---:|
| 标题 / 艺术家 / 专辑 | ✓ | ✓ | ✓ |
| 专辑艺术家 | TPE2 | ALBUMARTIST | aART |
| 作曲家 | TCOM | COMPOSER | ©wrt |
| 词作者 | TEXT | LYRICIST | ✗（无标准原子） |
| 年份 / 类型 | ✓ | ✓ | ✓ |
| 音轨号 / 光盘号 | TRCK / TPOS | TRACKNUMBER / DISCNUMBER | trkn / disk |
| 注释 | COMM | COMMENT | ©cmt |
| 版权 | TCOP | COPYRIGHT | cprt |
| 封面 | APIC | PICTURE | covr |
| 歌词 | USLT | LYRICS | ©lyr |

## 持久化授权说明

鸿蒙系统出于安全考虑，文件选择器授予的权限默认是临时的，App 重启后失效。为实现「长期访问/回写某个文件」，本应用使用 `@kit.CoreFileKit` 的 `fileShare` 接口：

1. **导入时** `persistPermission`：持久化所选 URI 的读写权限；
2. **每次启动/进入编辑前** `activatePermission`：激活已持久化的权限；
3. **从列表删除时** `revokePermission`：回收权限。

需在 `module.json5` 声明 `ohos.permission.FILE_ACCESS_PERSIST`。
参考文档：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/file-persistpermission>

> 注：以上接口在部分设备/模拟器上可能不可用，代码已做降级处理——授权失败不阻断流程，至少保证本次会话内可正常读写。

## 技术架构

- **CoreFileKit**：`DocumentViewPicker` 选择文件、`fileIo` 二进制读写、`fileShare` 持久化授权
- **MediaKit**：`AVMetadataExtractor` 补充时长 / 无标签时回退
- **ArkData Preferences**：持久化已导入文件列表
- **ImageKit**：封面图片编解码
- **ArkUI Navigation**：主页列表 ↔ 编辑页的页面栈导航
- **纯 ArkTS 标签编解码**：不依赖系统写 API，直接按 ID3v2 / FLAC / MP4 规范读写

## 文件结构

```
entry/src/main/ets/
├── model/
│   ├── AudioMetadata.ets          # 音频元数据模型
│   └── AudioFileEntry.ets         # 列表项模型（已导入文件）
├── service/
│   ├── AudioMetadataService.ets       # 读取元数据（解析 + 系统 API 补充）
│   ├── AudioMetadataWriteService.ets  # 按格式分派、原地写回文件
│   ├── FileListStorageService.ets     # Preferences 存取文件列表
│   ├── FilePermissionService.ets      # fileShare 持久化授权
│   ├── FilePickerService.ets          # 文件 / 图片选择
│   ├── Id3v2Reader.ets / Id3v2Writer.ets   # MP3 (ID3v2) 读写
│   ├── FlacReader.ets / FlacWriter.ets     # FLAC (Vorbis) 读写
│   └── M4aReader.ets / M4aWriter.ets       # M4A (MP4 ilst) 读写
├── pages/
│   ├── Index.ets                  # 主页：文件列表 + 悬浮导入按钮
│   └── AudioTagEditorPage.ets     # 标签编辑页（Navigation 子页）
└── entryability/
    └── EntryAbility.ets           # 入口，配置沉浸式窗口
```

## 使用方法

1. 启动应用，进入文件列表主页。
2. 点击右下角悬浮「+」按钮，选择一个或多个音频文件导入（导入即持久化授权）。
3. 点击列表项进入编辑页，查看并修改标签、封面、歌词。
4. 点击「写入文件」将标签原地写回原始音频文件。
5. 右滑列表项可将文件移出列表（同时回收其持久化授权）。

> 提示：写入为原地覆盖，建议先备份重要文件。
