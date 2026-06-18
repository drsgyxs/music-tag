/**
 * 主页：已导入音频文件列表
 *
 * - 文件列表模式：展示用户导入并持久化授权的音频文件；
 * - 右下角悬浮按钮导入新文件（DocumentViewPicker 多选 + 持久化授权）；
 * - 点击列表项进入标签编辑页（Navigation 子页）；
 * - 右滑列表项可删除（同时回收持久化授权）。
 */
import { AudioFileEntry, AudioFileEntryHelper } from '../model/AudioFileEntry';
import { FileListStorageService } from '../service/FileListStorageService';
import { FilePermissionService } from '../service/FilePermissionService';
import { FilePickerService } from '../service/FilePickerService';
import { AudioMetadataService } from '../service/AudioMetadataService';
import { GripPostureService } from '../service/GripPostureService';
import { LUMINANCE_SUPPORTED } from '../common/Luminance';
import { AudioTagEditorPage } from './AudioTagEditorPage';
import { motion } from '@kit.MultimodalAwarenessKit';

import { HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController, HdsNavigationMenuContentOptions, ScrollEffectType, hdsMaterial,
  HideMode } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  @State fileList: AudioFileEntry[] = [];
  @State isImporting: boolean = false;
  @State toastMessage: string = '';
  // 智感握姿：驱动悬浮按钮左下/右下切换
  @State holdingHand: motion.HoldingHandStatus = motion.HoldingHandStatus.RIGHT_HAND_HELD;
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack();
  @StorageProp('topRectHeight')
  topRectHeight: number = 0;

  private storageService: FileListStorageService = FileListStorageService.getInstance();
  private permissionService: FilePermissionService = FilePermissionService.getInstance();
  private filePickerService: FilePickerService = FilePickerService.getInstance();
  private metadataService: AudioMetadataService = AudioMetadataService.getInstance();
  private gripService: GripPostureService = GripPostureService.getInstance();
  private toastTimer: number = -1;
  private gripListener: (status: motion.HoldingHandStatus) => void = (status) => {
    this.getUIContext().animateTo({ duration: 160, curve: Curve.FastOutSlowIn }, () => {
      this.holdingHand = status;
    });
  };

  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.refreshList();
    this.holdingHand = this.gripService.addListener(this.gripListener);
  }

  aboutToDisappear(): void {
    this.gripService.removeListener(this.gripListener);
  }

  /** 加载列表并激活已持久化的文件权限 */
  private refreshList(): void {
    this.fileList = this.storageService.loadList();
    if (this.fileList.length > 0) {
      const uris = this.fileList.map((e) => e.uri);
      this.permissionService.activate(uris);
    }
  }

  private showToast(msg: string): void {
    this.toastMessage = msg;
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout(() => {
      this.toastMessage = '';
      this.toastTimer = -1;
    }, 2500);
  }

  /** 智感握姿：左手→左下，右手/双手/未识别→右下 */
  private fabAlignment(): Alignment {
    return this.holdingHand === motion.HoldingHandStatus.LEFT_HAND_HELD
      ? Alignment.BottomStart
      : Alignment.BottomEnd;
  }

  /** 悬浮按钮外边距：随握姿贴左或贴右 */
  private fabMargin(): Margin {
    return this.holdingHand === motion.HoldingHandStatus.LEFT_HAND_HELD
      ? { left: 20, bottom: 40 }
      : { right: 20, bottom: 40 };
  }

  // ===================== 构建入口 =====================
  build() {
    HdsNavigation(this.pageStack) {
      if (this.fileList.length === 0) {
        this.EmptyView()
      } else {
        this.FileListView()
      }
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .titleBar({
      content: {
        title: {
          mainTitle: '音乐标签',
        },
        menu: {
          value: [{
            content: {
              label: '导入',
              icon: $r('sys.symbol.plus'),
              action: () => {
                this.importFiles();
              }
            },
          }]
        }
      },
      enableComponentSafeArea: true, // 将标题栏设置为组件级安全区，内容区可避让标题栏
      style: {
        scrollEffectOpts: {
          // 设置导航组件标题栏样式，推荐使用默认样式
          // 标题栏动态模糊样式，包括是否使能滚动动态模糊，动态模糊类型，动态模糊生效的滚动距离等
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        originalStyle: {
          // 内容区滚动前初始样式设置
          backgroundStyle: {
            // 标题栏背板样式设置
            backgroundColor: $r('sys.color.ohos_id_color_background'),
          },
          contentStyle: {
            // 标题栏内容区样式设置，包括标题区域，菜单区域，返回按钮区域
            titleStyle: {
              mainTitleColor: $r('sys.color.font_primary'),
              subTitleColor: $r('sys.color.font_secondary')
            },
            menuStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            },
            backIconStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            }
          }
        },
        scrollEffectStyle: {
          // 内容区滚动超过blurEffectiveEndOffset后样式设置
          backgroundStyle: {
            backgroundColor: $r('sys.color.ohos_id_color_background_transparent')
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: $r('sys.color.font_primary'),
              subTitleColor: $r('sys.color.font_secondary')
            },
            menuStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            },
            backIconStyle: {
              backgroundColor: $r('sys.color.comp_background_tertiary'),
              iconColor: $r('sys.color.icon_primary')
            }
          }
        },
      },
    })
    .dynamicHideTitleBar({
      hideTitleArea: true,
      hideBottomBuilder: true,
      hideStatusBar: false,
      mode: HideMode.SCROLL_UP
    })
    .hideBackButton(true)
    .bindToScrollable([this.scroller]) // 绑定导航组件和可滚动容器组件
    // .navDestination(this.EditorDestination)
    .titleMode(HdsNavigationTitleMode.MINI)
  }

  // ===================== 编辑页（NavDestination） =====================
  @Builder
  EditorDestination(name: string, param: object) {
    NavDestination() {
      if (name === 'editor') {
        AudioTagEditorPage({ fileEntry: param as AudioFileEntry })
      }
    }
    .title((param as AudioFileEntry).fileName)
    .mode(NavDestinationMode.STANDARD)
  }

  // ===================== 空列表引导 =====================
  @Builder
  EmptyView() {
    Column() {
      Image($r('app.media.startIcon'))
        .width(96)
        .height(96)
        .borderRadius(20)
        .margin({ bottom: 20 })

      Text('还没有导入音频文件')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#2C3E50')
        .margin({ bottom: 8 })

      Text('点击右下角「+」导入 MP3、FLAC、M4A 文件\n导入后可长期访问并编辑其标签')
        .fontSize(13)
        .fontColor('#7F8C8D')
        .textAlign(TextAlign.Center)
        .lineHeight(20)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // ===================== 文件列表 =====================
  @Builder
  FileListView() {
    List({ space: 12, initialIndex: 0, scroller: this.scroller }) {
      ForEach(this.fileList, (item: AudioFileEntry) => {
        ListItem() {
          this.FileItem(item)
        }
        .swipeAction({ end: this.DeleteButton(item) })
      }, (item: AudioFileEntry) => item.uri)
    }
    .width('100%')
    .padding({ top: 12, left: 12, right: 12, bottom: 16 })
    .clip(false) // 设置不对子组件超出当前组件范围外的区域进行裁剪，使内容区可以穿透到标题栏下方
    .cachedCount(3, true) // 设置列表中ListItem/ListItemGroup的预加载数量，列表穿透到标题栏下方不会消失
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .height('auto')
  }

  @Builder
  FileItem(item: AudioFileEntry) {
    Row() {
      // 格式图标
      Column() {
        Text(item.fileFormat.toUpperCase())
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_on_primary'))
      }
      .width(44)
      .height(44)
      .borderRadius(10)
      .backgroundColor($r('sys.color.brand'))
      .justifyContent(FlexAlign.Center)
      .margin({ right: 12 })

      Column() {
        Text(item.fileName)
          .fontSize(15)
          .fontColor($r('sys.color.font_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.metadataService.formatFileSize(item.fileSize))
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(22)
        .fontColor([$r('sys.color.font_secondary')])
        .margin({ left: 8 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(12)
    .onClick(() => {
      this.openEditor(item);
    })
  }

  @Builder
  DeleteButton(item: AudioFileEntry) {
    Button({ type: ButtonType.Normal }) {
      Text('删除')
        .fontSize(14)
        .fontColor('#FFFFFF')
    }
    .width(72)
    .height('100%')
    .backgroundColor('#E74C3C')
    .borderRadius(12)
    .margin({ left: 8 })
    .onClick(() => {
      this.removeFile(item);
    })
  }

  // ===================== 悬浮导入按钮 =====================
  @Builder
  ImportFab() {
    // 智感握姿：左手握持贴左、否则贴右，避让到拇指可达侧
    Button({ type: ButtonType.Circle }) {
      if (this.isImporting) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(LUMINANCE_SUPPORTED ? '#3F51B5' : '#FFFFFF')
      } else {
        Text('+')
          .fontSize(32)
          .fontColor(LUMINANCE_SUPPORTED ? '#3F51B5' : '#FFFFFF')
      }
    }
    .width(56)
    .height(56)
    // 沉浸光感：透明底 + 材质；不支持时回退品牌纯色
    .backgroundColor(LUMINANCE_SUPPORTED ? Color.Transparent : '#3F51B5')
    .backdropBlur(12)
    .borderWidth(1)
    .borderColor('#FFFFFF')
    .margin(this.fabMargin())
    .enabled(!this.isImporting)
    .onClick(() => {
      this.importFiles();
    })
  }

  // ===================== 轻提示 =====================
  @Builder
  Toast() {
    Column() {
      Text(this.toastMessage)
        .fontSize(13)
        .fontColor('#FFFFFF')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor('#333333')
        .borderRadius(10)
    }
    .width('100%')
    .position({ x: 0, y: '85%' })
    .alignItems(HorizontalAlign.Center)
  }

  // ===================== 业务方法 =====================
  /** 导入音频文件：多选 → 持久化授权 → 写入列表 */
  async importFiles(): Promise<void> {
    if (this.isImporting) {
      return;
    }
    try {
      this.isImporting = true;
      const selected = await this.filePickerService.selectMultipleAudioFilesByDocumentPicker(500);
      if (selected.length === 0) {
        return;
      }

      // 持久化授权，确保 App 重启后仍可访问与回写
      const uris = selected.map((f) => f.uri);
      await this.permissionService.persist(uris);

      const now: number = new Date().getTime();
      const entries: AudioFileEntry[] = selected.map((f): AudioFileEntry => {
        return {
          uri: f.uri,
          fileName: f.fileName,
          fileFormat: AudioFileEntryHelper.extractFormat(f.fileName),
          fileSize: f.fileSize,
          addedTime: now
        };
      });

      this.fileList = this.storageService.addEntries(entries);
      this.showToast(`已导入 ${entries.length} 个文件`);
    } catch (error) {
      console.error('导入文件失败:', error);
      this.showToast(`导入失败: ${error}`);
    } finally {
      this.isImporting = false;
    }
  }

  /** 打开编辑页 */
  private openEditor(item: AudioFileEntry): void {
    // 进入前再激活一次该文件权限，规避会话内权限失效
    this.permissionService.activate([item.uri]);
    this.pageStack.pushPath({ name: 'editor', param: item });
  }

  /** 删除文件：从列表移除并回收授权 */
  private async removeFile(item: AudioFileEntry): Promise<void> {
    this.fileList = this.storageService.removeEntry(item.uri);
    await this.permissionService.revoke(item.uri);
    this.showToast('已从列表移除');
  }
}
