/**
 * 音乐标签编辑器页面（Navigation 子页）
 * 接收主页传入的文件项，读取、显示并编辑其元数据标签。
 */
import { AudioMetadata, AudioMetadataBuilder } from '../model/AudioMetadata';
import { AudioFileEntry } from '../model/AudioFileEntry';
import { AudioMetadataService } from '../service/AudioMetadataService';
import { FilePickerService } from '../service/FilePickerService';
import { AudioMetadataWriteService } from '../service/AudioMetadataWriteService';
import { GripPostureService } from '../service/GripPostureService';
import { LUMINANCE_SUPPORTED } from '../common/Luminance';
import { Id3TagInput } from '../service/Id3v2Writer';
import { image } from '@kit.ImageKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { HdsNavDestination, HdsNavigationTitleMode, HdsTabs, HdsTabsController, HdsNavigationMenuContentOptions, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';

@Builder
export function AudioTagEditorPageBuilder(name: string, param: object) {
  AudioTagEditorPage({ fileEntry: param as AudioFileEntry });
}


@Component
export struct AudioTagEditorPage {
  // 主页传入的文件项
  @Require @Prop fileEntry: AudioFileEntry;
  @Consume('pageStack') pageStack: NavPathStack;

  // ===================== 状态变量 =====================
  @State currentMetadata: AudioMetadata = AudioMetadataBuilder.createDefault();
  @State isLoading: boolean = false;
  @State isWriting: boolean = false;
  @State hasSelectedFile: boolean = false;
  @State coverPixelMap: image.PixelMap | null = null;
  @State errorMessage: string = '';
  @State successMessage: string = '';

  // 编辑字段
  @State editTitle: string = '';
  @State editArtist: string = '';
  @State editAlbum: string = '';
  @State editYear: string = '';
  @State editGenre: string = '';
  @State editComment: string = '';
  @State editLyrics: string = '';

  // 详细信息编辑字段
  @State editComposer: string = '';
  @State editWriter: string = '';
  @State editAlbumArtist: string = '';
  @State editTrackNumber: string = '';
  @State editDiscNumber: string = '';
  @State editCopyright: string = '';

  // 导出弹窗
  @State showExportDialog: boolean = false;

  // 歌词展开/折叠
  @State lyricsExpanded: boolean = false;

  // 智感握姿：驱动写入悬浮按钮左下/右下切换
  @State holdingHand: motion.HoldingHandStatus = motion.HoldingHandStatus.RIGHT_HAND_HELD;

  // 服务实例
  private metadataService: AudioMetadataService = AudioMetadataService.getInstance();
  private filePickerService: FilePickerService = FilePickerService.getInstance();
  private metadataWriteService: AudioMetadataWriteService = AudioMetadataWriteService.getInstance();
  private gripService: GripPostureService = GripPostureService.getInstance();

  // 消息自动隐藏计时器
  private successTimer: number = -1;
  private errorTimer: number = -1;
  private gripListener: (status: motion.HoldingHandStatus) => void = (status) => {
    this.getUIContext().animateTo({ duration: 160, curve: Curve.FastOutSlowIn }, () => {
      this.holdingHand = status;
    });
  };

  aboutToAppear(): void {
    this.loadMetadataFromEntry();
    this.holdingHand = this.gripService.addListener(this.gripListener);
  }

  aboutToDisappear(): void {
    this.gripService.removeListener(this.gripListener);
  }

  /** 写入悬浮按钮外边距：随握姿贴左或贴右 */
  private fabMargin(): Margin {
    return this.holdingHand === motion.HoldingHandStatus.LEFT_HAND_HELD
      ? { left: 20, bottom: 40 }
      : { right: 20, bottom: 40 };
  }

  // ===================== 消息工具 =====================
  private showSuccess(msg: string): void {
    this.successMessage = msg;
    this.errorMessage = '';
    if (this.successTimer >= 0) clearTimeout(this.successTimer);
    this.successTimer = setTimeout(() => {
      this.successMessage = '';
      this.successTimer = -1;
    }, 2500);
  }

  private showError(msg: string): void {
    this.errorMessage = msg;
    this.successMessage = '';
    if (this.errorTimer >= 0) clearTimeout(this.errorTimer);
    this.errorTimer = setTimeout(() => {
      this.errorMessage = '';
      this.errorTimer = -1;
    }, 3500);
  }

  /** 智感握姿：左手→左下，右手/双手/未识别→右下 */
  private fabAlignment(): Alignment {
    return this.holdingHand === motion.HoldingHandStatus.LEFT_HAND_HELD
      ? Alignment.BottomStart
      : Alignment.BottomEnd;
  }

  // ===================== 构建入口 =====================
  build() {
    HdsNavDestination() {
      Column() {
        if (this.isLoading) {
          this.LoadingView()
        } else if (!this.hasSelectedFile) {
          this.NoFileView()
        } else {
          this.EditorView()
        }
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('sys.color.background_secondary'))
    .titleBar({
      content: {
        title: {
          mainTitle: this.fileEntry.fileName,
        },
        menu: {
          value: [{
            content: {
              label: '保存',
              icon: $r('sys.symbol.checkmark'),
              action: () => {
                this.writeTagsToFile();
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
  }

  // ===================== 写入文件悬浮按钮 =====================
  @Builder
  WriteFab() {
    // 智感握姿：左手握持贴左、否则贴右；沉浸光感：透明底 + 材质，降级回退纯色
    Button({ type: ButtonType.Circle }) {
      if (this.isWriting) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(LUMINANCE_SUPPORTED ? '#009688' : '#FFFFFF')
      } else {
        Text('💾')
          .fontSize(24)
      }
    }
    .width(56)
    .height(56)
    .backgroundColor(LUMINANCE_SUPPORTED ? Color.Transparent : '#009688')
    .shadow({ radius: 12, color: '#40000000', offsetX: 0, offsetY: 4 })
    .margin(this.fabMargin())
    .enabled(!this.isWriting)
    .onClick(() => {
      this.writeTagsToFile();
    })
  }

  // ===================== 加载中 =====================
  @Builder
  LoadingView() {
    Column() {
      LoadingProgress()
        .width(56)
        .height(56)
        .color('#3F51B5')
      Text('正在读取音频信息...')
        .fontSize(15)
        .fontColor('#666666')
        .margin({ top: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // ===================== 加载失败 =====================
  @Builder
  NoFileView() {
    Column() {
      Text('😕')
        .fontSize(48)
        .margin({ bottom: 16 })
      Text('未能读取该文件')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#2C3E50')
        .margin({ bottom: 8 })
      Text('文件可能已被移动、删除，或访问权限已失效')
        .fontSize(13)
        .fontColor('#7F8C8D')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 28 })

      Button('重试')
        .width(160)
        .height(44)
        .fontSize(15)
        .backgroundColor('#3F51B5')
        .fontColor('#FFFFFF')
        .borderRadius(22)
        .onClick(() => {
          this.loadMetadataFromEntry();
        })

      Button('返回列表')
        .width(160)
        .height(44)
        .fontSize(15)
        .backgroundColor('#ECEFF1')
        .fontColor('#5C6BC0')
        .borderRadius(22)
        .margin({ top: 12 })
        .onClick(() => {
          this.pageStack.pop();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(24)
  }

  // ===================== 编辑器主视图 =====================
  @Builder
  EditorView() {
    Scroll() {
      Column() {
        this.CoverSection()
        this.BasicInfoSection()
        this.DetailInfoSection()
        this.LyricsSection()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 16 })
    }
    .clipContent(ContentClipMode.SAFE_AREA)
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  // ===================== 封面区域 =====================
  @Builder
  CoverSection() {
    Column() {
      Row() {
        this.CardHeaderText('🖼️ 专辑封面')
        Blank()
        Button({ type: ButtonType.Normal }) {
          Text(this.currentMetadata.hasCover ? '更换封面' : '添加封面')
            .fontSize(12)
            .fontColor($r('sys.color.brand'))
        }
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(14)
        .height(28)
        .padding({ left: 10, right: 10 })
        .onClick(() => {
          this.selectCoverImage();
        })
      }
      .width('100%')
      .margin({ bottom: 14 })

      if (this.coverPixelMap) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Image(this.coverPixelMap)
            .width(180)
            .height(180)
            .objectFit(ImageFit.Cover)
            .borderRadius(12)
            .shadow({ radius: 8, color: '#20000000', offsetX: 0, offsetY: 2 })

          Text('已更新')
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor('#4CAF50')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .margin({ right: 6, bottom: 6 })
            .visibility(this.currentMetadata.hasCover ? Visibility.Hidden : Visibility.Visible)
        }
      } else if (this.currentMetadata.hasCover) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color('#3F51B5')
          Text('加载封面中...')
            .fontSize(12)
            .fontColor('#7F8C8D')
            .margin({ top: 8 })
        }
        .width(180)
        .height(180)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#ECEFF1')
        .borderRadius(12)
      } else {
        Column() {
          Text('🎵')
            .fontSize(48)
          Text('暂无封面')
            .fontSize(13)
            .fontColor('#BDC3C7')
            .margin({ top: 8 })
        }
        .width(180)
        .height(180)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#ECEFF1')
        .borderRadius(12)
      }
    }
    .cardStyle()
    .margin({ bottom: 10 })
    .alignItems(HorizontalAlign.Center)
  }

  // ===================== 基础信息编辑 =====================
  @Builder
  BasicInfoSection() {
    Column() {
      this.CardHeader('✏️ 基础标签')

      this.EditFieldItem('标题', this.editTitle, '歌曲标题', (v) => { this.editTitle = v; })
      this.EditFieldItem('艺术家', this.editArtist, '演唱者', (v) => { this.editArtist = v; })
      this.EditFieldItem('专辑', this.editAlbum, '专辑名称', (v) => { this.editAlbum = v; })
      this.EditFieldItem('年份', this.editYear, '发行年份，如 2024', (v) => { this.editYear = v; })
      this.EditFieldItem('类型', this.editGenre, '音乐类型，如 Pop、Rock', (v) => { this.editGenre = v; })
    }
    .cardStyle()
    .margin({ bottom: 10 })
  }

  @Builder
  EditFieldItem(label: string, value: string, placeholder: string, onChange: (v: string) => void) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .margin({ bottom: 4 })
      TextInput({ text: value, placeholder: placeholder })
        .width('100%')
        .height(40)
        .backgroundColor($r('sys.color.comp_background_gray'))
        .borderRadius(8)
        .fontSize(14)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .onChange((v: string) => onChange(v))
    }
    .width('100%')
    .margin({ bottom: 14 })
  }

  /** 当前格式不支持编辑的字段：只读展示并附说明 */
  @Builder
  UnsupportedFieldItem(label: string, value: string, reason: string) {
    Column() {
      Row() {
        Text(label)
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
        Text('不支持')
          .fontSize(10)
          .fontColor('#E67E22')
          .backgroundColor('#FDEBD0')
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .borderRadius(8)
          .margin({ left: 6 })
      }
      .width('100%')
      .margin({ bottom: 4 })

      TextInput({ text: value })
        .width('100%')
        .height(40)
        .backgroundColor($r('sys.color.background_primary'))
        .borderRadius(8)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .enabled(false)
      Text(reason)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .margin({ bottom: 14 })
  }

  // ===================== 详细信息 =====================
  @Builder
  DetailInfoSection() {
    Column() {
      this.CardHeader('ℹ️ 详细信息')

      this.EditFieldItem('作曲家', this.editComposer, '作曲', (v) => { this.editComposer = v; })
      // 词作者：M4A/MP4/AAC 无对应标准标签，禁用编辑
      if (this.isWriterSupported()) {
        this.EditFieldItem('词作者', this.editWriter, '作词', (v) => { this.editWriter = v; })
      } else {
        this.UnsupportedFieldItem('词作者', this.editWriter, '当前格式不支持写入词作者')
      }
      this.EditFieldItem('专辑艺术家', this.editAlbumArtist, '专辑艺术家', (v) => { this.editAlbumArtist = v; })
      this.EditFieldItem('音轨号', this.editTrackNumber, '如 3 或 3/12', (v) => { this.editTrackNumber = v; })
      this.EditFieldItem('光盘号', this.editDiscNumber, '如 1 或 1/2', (v) => { this.editDiscNumber = v; })
      this.EditFieldItem('版权', this.editCopyright, '版权信息', (v) => { this.editCopyright = v; })

      // 注释（可编辑）
      Column() {
        Text('注释')
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .margin({ bottom: 4 })
        TextArea({ text: this.editComment, placeholder: '添加注释...' })
          .width('100%')
          .height(80)
          .backgroundColor($r('sys.color.comp_background_gray'))
          .borderRadius(8)
          .fontSize(14)
          .fontColor($r('sys.color.font_primary'))
          .placeholderColor($r('sys.color.font_tertiary'))
          .onChange((v: string) => { this.editComment = v; })
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .cardStyle()
    .margin({ bottom: 10 })
  }

  // ===================== 歌词区域 =====================
  @Builder
  LyricsSection() {
    Column() {
      Row() {
        this.CardHeaderText('📝 歌词')
        Blank()
        if (this.currentMetadata.hasLyrics) {
          Text('已嵌入')
            .fontSize(11)
            .fontColor('#27AE60')
            .backgroundColor('#E8F8F5')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .margin({ right: 8 })
        } else {
          Text('无内嵌歌词')
            .fontSize(11)
            .fontColor('#95A5A6')
            .backgroundColor('#F2F3F7')
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .margin({ right: 8 })
        }
        // 展开/折叠按钮
        if (this.editLyrics.length > 0) {
          Button({ type: ButtonType.Normal }) {
            Text(this.lyricsExpanded ? '折叠' : '展开')
              .fontSize(11)
              .fontColor('#3F51B5')
          }
          .backgroundColor('#E8EAF6')
          .borderRadius(12)
          .height(24)
          .padding({ left: 8, right: 8 })
          .onClick(() => {
            this.lyricsExpanded = !this.lyricsExpanded;
          })
        }
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 歌词说明
      if (!this.currentMetadata.hasLyrics) {
        Text('未检测到内嵌歌词，您可以在下方手动输入歌词')
          .fontSize(12)
          .fontColor('#7F8C8D')
          .width('100%')
          .margin({ bottom: 8 })
      }

      // 歌词编辑区
      TextArea({ text: this.editLyrics, placeholder: '在此输入或编辑歌词...\n支持 LRC 格式，如：[00:10.00] 第一行歌词' })
        .width('100%')
        .height(this.lyricsExpanded ? 400 : 160)
        .backgroundColor($r('sys.color.comp_background_gray'))
        .borderRadius(8)
        .fontSize(13)
        .fontColor($r('sys.color.font_primary'))
        .placeholderColor($r('sys.color.font_tertiary'))
        .onChange((v: string) => {
          this.editLyrics = v;
        })

      // LRC 格式提示
      if (this.editLyrics.length > 0 && this.editLyrics.includes('[')) {
        Text('✓ 检测到 LRC 时间戳格式')
          .fontSize(11)
          .fontColor('#27AE60')
          .width('100%')
          .margin({ top: 4 })
      }
    }
    .cardStyle()
    .margin({ bottom: 10 })
  }


  // ===================== 消息浮层 =====================
  @Builder
  MessageToast() {
    Column() {
      if (this.errorMessage) {
        Row() {
          Text('✕')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .margin({ right: 8 })
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
        }
        .width('88%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor('#E74C3C')
        .borderRadius(10)
        .margin({ bottom: 8 })
        .shadow({ radius: 8, color: '#30000000', offsetX: 0, offsetY: -2 })
      }

      if (this.successMessage) {
        Row() {
          Text('✓')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .margin({ right: 8 })
          Text(this.successMessage)
            .fontSize(13)
            .fontColor('#FFFFFF')
            .layoutWeight(1)
        }
        .width('88%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor('#27AE60')
        .borderRadius(10)
        .margin({ bottom: 8 })
        .shadow({ radius: 8, color: '#30000000', offsetX: 0, offsetY: -2 })
      }
    }
    .width('100%')
    .padding({ bottom: 20 })
    .alignItems(HorizontalAlign.Center)
  }

  // ===================== 通用子组件 =====================
  @Builder
  CardHeader(title: string) {
    Text(title)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
      .width('100%')
      .margin({ bottom: 14 })
  }

  @Builder
  CardHeaderText(title: string) {
    Text(title)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_primary'))
  }

  @Builder
  InfoRow2(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#7F8C8D')
        .width(88)
        .flexShrink(0)
      Text(value || '未知')
        .fontSize(13)
        .fontColor(value ? '#2C3E50' : '#BDC3C7')
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .borderWidth({ bottom: 0.5 })
    .borderColor('#F0F0F0')
    .margin({ bottom: 2 })
  }

  // ===================== 业务方法 =====================
  /**
   * 当前文件格式是否支持写入「词作者」。
   * M4A/MP4/AAC 的 iTunes 标签体系无标准的作词(lyricist)原子，故不支持。
   */
  private isWriterSupported(): boolean {
    const fmt: string = this.currentMetadata.fileFormat.toLowerCase();
    return fmt !== 'm4a' && fmt !== 'mp4' && fmt !== 'aac';
  }

  /**
   * 读取主页传入文件的元数据
   */
  async loadMetadataFromEntry(): Promise<void> {
    try {
      this.isLoading = true;
      this.hasSelectedFile = false;
      this.errorMessage = '';
      this.successMessage = '';
      this.coverPixelMap = null;

      // 读取元数据（uri 已在主页持久化并激活授权）
      const metadata = await this.metadataService.readMetadataFromUri(this.fileEntry.uri);
      // 文件名/大小以列表项为准，避免 uri 解析差异
      metadata.fileName = this.fileEntry.fileName;
      if (this.fileEntry.fileSize > 0) {
        metadata.fileSize = this.fileEntry.fileSize;
      }

      this.currentMetadata = metadata;
      this.hasSelectedFile = true;

      // 同步编辑字段
      this.editTitle = metadata.title;
      this.editArtist = metadata.artist;
      this.editAlbum = metadata.album;
      this.editYear = metadata.year;
      this.editGenre = metadata.genre;
      this.editComment = metadata.comment;
      this.editLyrics = metadata.lyrics;
      this.editComposer = metadata.composer;
      this.editWriter = metadata.writer;
      this.editAlbumArtist = metadata.albumArtist;
      this.editTrackNumber = metadata.trackNumber;
      this.editDiscNumber = metadata.discNumber;
      this.editCopyright = metadata.copyright;
      this.lyricsExpanded = false;

      // 加载封面
      if (metadata.coverImage) {
        this.coverPixelMap = metadata.coverImage;
      } else if (metadata.coverImagePath) {
        this.coverPixelMap = await this.metadataService.loadCoverImage(metadata.coverImagePath);
      }
    } catch (error) {
      console.error('读取音频文件失败:', error);
      this.hasSelectedFile = false;
      this.showError(`加载失败: ${error}`);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 更换封面图片
   */
  async selectCoverImage(): Promise<void> {
    const promptAction = this.getUIContext().getPromptAction();
    try {
      const imageUri = await this.filePickerService.selectImageFile();
      if (imageUri) {
        const pixelMap = await this.metadataService.loadCoverImage(imageUri);
        if (pixelMap) {
          this.coverPixelMap = pixelMap;
          this.currentMetadata.hasCover = true;
          promptAction.showToast({
            message: '封面已更新'
          })
        }
      }
    } catch (error) {
      console.error('选择封面失败:', error);
      promptAction.showToast({
        message: `选择封面失败${error}`
      })
    }
  }

  /**
   * 将编辑后的标签以 ID3v2.3 格式原地写入音频文件
   */
  async writeTagsToFile(): Promise<void> {
    if (this.isWriting) {
      return;
    }

    const fmt = this.currentMetadata.fileFormat.toLowerCase();
    const isM4a: boolean = fmt === 'm4a' || fmt === 'mp4' || fmt === 'aac';
    const promptAction = this.getUIContext().getPromptAction();

    try {
      if (fmt !== 'mp3' && fmt !== 'flac' && !isM4a) {
        promptAction.showToast({
          message: '当前仅支持写入 MP3、FLAC、M4A 文件'
        });
        return;
      }
      this.isWriting = true;

      // 同步编辑字段到 currentMetadata
      this.currentMetadata.title = this.editTitle;
      this.currentMetadata.artist = this.editArtist;
      this.currentMetadata.album = this.editAlbum;
      this.currentMetadata.year = this.editYear;
      this.currentMetadata.genre = this.editGenre;
      this.currentMetadata.comment = this.editComment;
      this.currentMetadata.lyrics = this.editLyrics;
      this.currentMetadata.hasLyrics = this.editLyrics.trim().length > 0;
      this.currentMetadata.composer = this.editComposer;
      this.currentMetadata.albumArtist = this.editAlbumArtist;
      this.currentMetadata.trackNumber = this.editTrackNumber;
      this.currentMetadata.discNumber = this.editDiscNumber;
      this.currentMetadata.copyright = this.editCopyright;
      // 词作者仅在受支持的格式下写入
      if (this.isWriterSupported()) {
        this.currentMetadata.writer = this.editWriter;
      }

      // 组装标签输入
      const input: Id3TagInput = {
        title: this.currentMetadata.title,
        artist: this.currentMetadata.artist,
        album: this.currentMetadata.album,
        albumArtist: this.currentMetadata.albumArtist,
        composer: this.currentMetadata.composer,
        writer: this.isWriterSupported() ? this.currentMetadata.writer : '',
        year: this.currentMetadata.year,
        genre: this.currentMetadata.genre,
        trackNumber: this.currentMetadata.trackNumber,
        discNumber: this.currentMetadata.discNumber,
        comment: this.currentMetadata.comment,
        copyright: this.currentMetadata.copyright,
        lyrics: this.currentMetadata.lyrics
      };

      // 封面：将 PixelMap 编码为 JPEG 字节
      if (this.coverPixelMap) {
        try {
          input.coverData = await this.metadataService.pixelMapToArrayBuffer(this.coverPixelMap);
          input.coverMime = 'image/jpeg';
        } catch (e) {
          console.error('封面编码失败，跳过封面写入:', e);
        }
      }

      await this.metadataWriteService.writeTags(this.currentMetadata.filePath, fmt, input);

      promptAction.showToast({
        message: '保存成功'
      });
    } catch (error) {
      console.error('写入文件失败:', error);
      promptAction.showToast({
        message: '保存失败'
      });
    } finally {
      this.isWriting = false;
    }
  }

}

// 样式扩展
@Extend(Column)
function cardStyle() {
  .width('100%')
  .padding(16)
  .backgroundColor($r('sys.color.comp_background_primary'))
  .borderRadius(14)
}
