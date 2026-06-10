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
import { AudioTagEditorPage } from './AudioTagEditorPage';

@Entry
@Component
struct Index {
  @State fileList: AudioFileEntry[] = [];
  @State isImporting: boolean = false;
  @State toastMessage: string = '';
  @Provide('pageStack') pageStack: NavPathStack = new NavPathStack();

  private storageService: FileListStorageService = FileListStorageService.getInstance();
  private permissionService: FilePermissionService = FilePermissionService.getInstance();
  private filePickerService: FilePickerService = FilePickerService.getInstance();
  private metadataService: AudioMetadataService = AudioMetadataService.getInstance();
  private toastTimer: number = -1;

  aboutToAppear(): void {
    this.refreshList();
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

  // ===================== 构建入口 =====================
  build() {
    Navigation(this.pageStack) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          if (this.fileList.length === 0) {
            this.EmptyView()
          } else {
            this.FileListView()
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F2F3F7')

        // 悬浮导入按钮
        this.ImportFab()

        // 轻提示
        if (this.toastMessage) {
          this.Toast()
        }
      }
      .width('100%')
      .height('100%')
      // 灰色背景铺到 Stack 自身，配合 expandSafeArea 延伸到底部「小白条」之下，避免出现白色空白
      .backgroundColor('#F2F3F7')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .title('🎵 音乐标签编辑器')
    .titleMode(NavigationTitleMode.Mini)
    .mode(NavigationMode.Stack)
    .navDestination(this.EditorDestination)
    .hideBackButton(true)
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
    Column() {
      Row() {
        Text(`已导入 ${this.fileList.length} 个文件`)
          .fontSize(13)
          .fontColor('#7F8C8D')
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      List({ space: 8 }) {
        ForEach(this.fileList, (item: AudioFileEntry) => {
          ListItem() {
            this.FileItem(item)
          }
          .swipeAction({ end: this.DeleteButton(item) })
        }, (item: AudioFileEntry) => item.uri)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, bottom: 88 })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  FileItem(item: AudioFileEntry) {
    Row() {
      // 格式图标
      Column() {
        Text(item.fileFormat.toUpperCase())
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .width(44)
      .height(44)
      .borderRadius(10)
      .backgroundColor('#3F51B5')
      .justifyContent(FlexAlign.Center)
      .margin({ right: 12 })

      Column() {
        Text(item.fileName)
          .fontSize(15)
          .fontColor('#2C3E50')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.metadataService.formatFileSize(item.fileSize))
          .fontSize(12)
          .fontColor('#95A5A6')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(22)
        .fontColor('#BDC3C7')
        .margin({ left: 8 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
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
    Button({ type: ButtonType.Circle }) {
      if (this.isImporting) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color('#FFFFFF')
      } else {
        Text('+')
          .fontSize(32)
          .fontColor('#FFFFFF')
      }
    }
    .width(56)
    .height(56)
    .backgroundColor('#3F51B5')
    .shadow({ radius: 12, color: '#40000000', offsetX: 0, offsetY: 4 })
    .margin({ right: 20, bottom: 40 })
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
      const selected = await this.filePickerService.selectMultipleAudioFilesByDocumentPicker();
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
