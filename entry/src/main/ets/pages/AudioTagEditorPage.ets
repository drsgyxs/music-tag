/**
 * 音乐标签编辑器主页面
 * 提供音频文件选择、元数据显示和编辑功能
 */
import { AudioMetadata, AudioMetadataBuilder } from '../model/AudioMetadata';
import { AudioMetadataService } from '../service/AudioMetadataService';
import { FilePickerService } from '../service/FilePickerService';
import { AudioMetadataWriteService } from '../service/AudioMetadataWriteService';
import { Id3TagInput } from '../service/Id3v2Writer';
import { image } from '@kit.ImageKit';

@Entry
@Component
struct AudioTagEditorPage {
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

  // 服务实例
  private metadataService: AudioMetadataService = AudioMetadataService.getInstance();
  private filePickerService: FilePickerService = FilePickerService.getInstance();
  private metadataWriteService: AudioMetadataWriteService = AudioMetadataWriteService.getInstance();

  // 消息自动隐藏计时器
  private successTimer: number = -1;
  private errorTimer: number = -1;

  aboutToAppear(): void {

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

  // ===================== 构建入口 =====================
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 标题栏
        this.TitleBar()

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
      .backgroundColor('#F2F3F7')

      // 消息提示浮层
      if (this.errorMessage || this.successMessage) {
        this.MessageToast()
      }
    }
    .width('100%')
    .height('100%')
  }

  // ===================== 标题栏 =====================
  @Builder
  TitleBar() {
    Row() {
      Text('🎵 音乐标签编辑器')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .layoutWeight(1)

      if (this.hasSelectedFile) {

        Button({ type: ButtonType.Normal }) {
          Text(this.isWriting ? '写入中…' : '写入文件')
            .fontSize(13)
            .fontColor('#FFFFFF')
        }
        .backgroundColor('#009688')
        .borderRadius(16)
        .height(30)
        .padding({ left: 12, right: 12 })
        .margin({ right: 8 })
        .enabled(!this.isWriting)
        .opacity(this.isWriting ? 0.6 : 1)
        .onClick(() => {
          this.writeTagsToFile();
        })

        Button({ type: ButtonType.Normal }) {
          Text('换文件')
            .fontSize(13)
            .fontColor('#FFFFFF')
        }
        .backgroundColor('#5C6BC0')
        .borderRadius(16)
        .height(30)
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          this.selectAudioFile();
        })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 12 })
    .backgroundColor('#3F51B5')
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

  // ===================== 未选文件 =====================
  @Builder
  NoFileView() {
    Scroll() {
      Column() {
        Image($r('app.media.startIcon'))
          .width(100)
          .height(100)
          .margin({ top: 40, bottom: 20 })
          .borderRadius(20)

        Text('欢迎使用音乐标签编辑器')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#2C3E50')
          .margin({ bottom: 8 })

        Text('选择音频文件以查看和编辑标签信息')
          .fontSize(14)
          .fontColor('#7F8C8D')
          .margin({ bottom: 32 })

        Button('选择音频文件')
          .width(200)
          .height(48)
          .fontSize(16)
          .backgroundColor('#3F51B5')
          .fontColor('#FFFFFF')
          .borderRadius(24)
          .onClick(() => {
            this.selectAudioFile();
          })

        // 功能说明卡片
        Column() {
          this.FeatureItem('🎵', '读取标签', '支持 MP3、FLAC、M4A、ACC 等格式')
          this.FeatureItem('✏️', '编辑标签', '修改标题、艺术家、专辑、年份等')
          this.FeatureItem('🖼️', '封面管理', '查看内嵌封面，支持更换图片')
          this.FeatureItem('📝', '歌词查看', '读取内嵌歌词，支持手动输入')
        }
        .width('88%')
        .padding(20)
        .margin({ top: 32, bottom: 24 })
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  FeatureItem(icon: string, title: string, desc: string) {
    Row() {
      Text(icon)
        .fontSize(22)
        .width(36)
        .textAlign(TextAlign.Center)
      Column() {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#2C3E50')
        Text(desc)
          .fontSize(12)
          .fontColor('#95A5A6')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .margin({ bottom: 14 })
  }

  // ===================== 编辑器主视图 =====================
  @Builder
  EditorView() {
    Scroll() {
      Column() {
        this.FileInfoCard()
        this.CoverSection()
        this.BasicInfoSection()
        this.DetailInfoSection()
        this.LyricsSection()
        this.NoticeSection()
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 24 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Fade)
  }

  // ===================== 文件信息卡片 =====================
  @Builder
  FileInfoCard() {
    Column() {
      this.CardHeader('📁 文件信息')

      this.InfoRow2('文件名', decodeURI(this.currentMetadata.fileName))
      this.InfoRow2('格式', this.currentMetadata.fileFormat.toUpperCase() || '未知')
      Row() {
        Column() {
          Text('文件大小')
            .fontSize(12)
            .fontColor('#95A5A6')
          Text(this.metadataService.formatFileSize(this.currentMetadata.fileSize))
            .fontSize(14)
            .fontColor('#2C3E50')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text('时长')
            .fontSize(12)
            .fontColor('#95A5A6')
          Text(this.metadataService.formatDuration(this.currentMetadata.duration))
            .fontSize(14)
            .fontColor('#2C3E50')
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .cardStyle()
    .margin({ bottom: 10 })
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
            .fontColor('#3F51B5')
        }
        .backgroundColor('#E8EAF6')
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
        .fontColor('#7F8C8D')
        .width('100%')
        .margin({ bottom: 4 })
      TextInput({ text: value, placeholder: placeholder })
        .width('100%')
        .height(40)
        .backgroundColor('#F4F6F8')
        .borderRadius(8)
        .fontSize(14)
        .fontColor('#2C3E50')
        .placeholderColor('#BDC3C7')
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
          .fontColor('#7F8C8D')
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
        .backgroundColor('#ECEFF1')
        .borderRadius(8)
        .fontSize(14)
        .fontColor('#BDC3C7')
        .enabled(false)
      Text(reason)
        .fontSize(11)
        .fontColor('#95A5A6')
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
          .fontColor('#7F8C8D')
          .width('100%')
          .margin({ bottom: 4 })
        TextArea({ text: this.editComment, placeholder: '添加注释...' })
          .width('100%')
          .height(80)
          .backgroundColor('#F4F6F8')
          .borderRadius(8)
          .fontSize(14)
          .fontColor('#2C3E50')
          .placeholderColor('#BDC3C7')
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
        .backgroundColor('#F4F6F8')
        .borderRadius(8)
        .fontSize(13)
        .fontColor('#2C3E50')
        .placeholderColor('#BDC3C7')
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

  // ===================== 注意事项 =====================
  @Builder
  NoticeSection() {
    Column() {
      Row() {
        Text('⚠️')
          .fontSize(16)
          .margin({ right: 6 })
        Text('说明')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#E67E22')
      }
      .width('100%')
      .margin({ bottom: 10 })

      Text('1. 点击「写入文件」会将标签直接写回原文件：MP3 采用 ID3v2.3，FLAC 采用 Vorbis Comment（均支持中文、封面、歌词）')
        .noticeTextStyle()
      Text('2. 写入为原地覆盖，建议先备份重要文件；若提示无写权限，请改用文档选择器选取本地存储中的文件')
        .noticeTextStyle()
      Text('3. 点击「保存」会将编辑内容存入应用本地存储（不修改原文件）')
        .noticeTextStyle()
      Text('4. 点击「导出」可将标签信息导出为 JSON / TXT / CSV 文件')
        .noticeTextStyle()
      Text('5. 目前标签读取与写入支持 MP3、FLAC、M4A，其他格式陆续支持中......')
        .noticeTextStyle()
      Text('6. 作曲家、词作者、专辑艺术家、音轨号、光盘号、版权均可编辑；其中「词作者」在 M4A 格式下无标准标签，故不支持写入')
        .noticeTextStyle()
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FEF9E7')
    .borderRadius(12)
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
      .fontColor('#2C3E50')
      .width('100%')
      .margin({ bottom: 14 })
  }

  @Builder
  CardHeaderText(title: string) {
    Text(title)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor('#2C3E50')
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
   * 选择音频文件
   */
  async selectAudioFile(): Promise<void> {
    try {
      this.isLoading = true;
      this.errorMessage = '';
      this.successMessage = '';

      // 使用文档选择器（DocumentViewPicker）选择文件，
      // 它授予临时读写权限，"写入文件"功能才能原地回写标签。
      const selectedFile = await this.filePickerService.selectAudioFileByDocumentPicker();

      if (!selectedFile) {
        this.isLoading = false;
        return;
      }
      this.coverPixelMap = null;

      // 读取元数据
      const metadata = await this.metadataService.readMetadataFromUri(selectedFile.uri);

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

      this.showSuccess('音频文件加载成功');
    } catch (error) {
      console.error('选择音频文件失败:', error);
      this.showError(`加载失败: ${error}`);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 更换封面图片
   */
  async selectCoverImage(): Promise<void> {
    try {
      const imageUri = await this.filePickerService.selectImageFile();
      if (imageUri) {
        const pixelMap = await this.metadataService.loadCoverImage(imageUri);
        if (pixelMap) {
          this.coverPixelMap = pixelMap;
          this.currentMetadata.hasCover = true;
          this.showSuccess('封面已更新');
        }
      }
    } catch (error) {
      console.error('选择封面失败:', error);
      this.showError(`选择封面失败: ${error}`);
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
    if (fmt !== 'mp3' && fmt !== 'flac' && !isM4a) {
      this.showError('当前仅支持写入 MP3、FLAC、M4A 文件');
      return;
    }

    try {
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

      this.showSuccess('标签已成功写入音频文件');
    } catch (error) {
      console.error('写入文件失败:', error);
      this.showError(`写入失败: ${error}`);
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
  .backgroundColor('#FFFFFF')
  .borderRadius(14)
}

@Extend(Text)
function noticeTextStyle() {
  .fontSize(13)
  .fontColor('#7F8C8D')
  .width('100%')
  .margin({ bottom: 6 })
  .lineHeight(20)
}
