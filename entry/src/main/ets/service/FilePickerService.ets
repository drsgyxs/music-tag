/**
 * 文件选择服务
 * 负责使用系统选择器选择音频文件
 */
import { picker } from '@kit.CoreFileKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

export interface SelectedAudioFile {
  uri: string;           // 文件URI
  fileName: string;      // 文件名
  fileSize: number;      // 文件大小
  filePath?: string;     // 文件路径（如果可获取）
}

export class FilePickerService {
  private static instance: FilePickerService;
  
  private constructor() {}
  
  static getInstance(): FilePickerService {
    if (!FilePickerService.instance) {
      FilePickerService.instance = new FilePickerService();
    }
    return FilePickerService.instance;
  }
  
  /**
   * 使用DocumentViewPicker选择音频文件（可写方案）
   *
   * 注意：必须使用 DocumentViewPicker 而非 AudioViewPicker。
   * AudioViewPicker / PhotoViewPicker 返回的媒体库 URI 仅授予“读”权限，
   * 无法以 READ_WRITE 打开回写（会报 Operation not permitted）。
   * DocumentViewPicker 会对所选文件授予临时读写权限，因此标签才能原地写回。
   * @returns 选中的音频文件信息
   */
  async selectAudioFileByDocumentPicker(): Promise<SelectedAudioFile | null> {
    try {
      const documentPicker = new picker.DocumentViewPicker();

      const documentSelectOptions: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = 1;
      // 目前支持读写 MP3 与 FLAC，选择器只显示这两种格式
      documentSelectOptions.fileSuffixFilters = ['音频文件|.mp3,.flac,.m4a,.aac'];

      const documentSelectResult = await documentPicker.select(documentSelectOptions);
      
      if (!documentSelectResult || documentSelectResult.length === 0) {
        console.info('用户取消了文件选择');
        return null;
      }
      
      const uri = documentSelectResult[0];
      const fileInfo = await this.getFileInfo(uri);
      
      return fileInfo;
    } catch (error) {
      console.error('使用DocumentPicker选择音频文件失败:', error);
      throw new Error(`选择音频文件失败: ${error}`);
    }
  }
  
  /**
   * 使用 DocumentViewPicker 多选音频文件（可写方案）
   *
   * 与单选同理，必须用 DocumentViewPicker 才能授予读写权限并支持持久化授权，
   * 以便后续原地回写标签。用于主页「导入」入口。
   * @param maxNumber 最大选择数量
   * @returns 选中的音频文件列表
   */
  async selectMultipleAudioFilesByDocumentPicker(maxNumber: number = 50): Promise<SelectedAudioFile[]> {
    try {
      const documentPicker = new picker.DocumentViewPicker();

      const documentSelectOptions: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = maxNumber;
      documentSelectOptions.fileSuffixFilters = ['音频文件|.mp3,.flac,.m4a,.aac'];

      const documentSelectResult: Array<string> = await documentPicker.select(documentSelectOptions);

      if (!documentSelectResult || documentSelectResult.length === 0) {
        console.info('用户取消了文件选择');
        return [];
      }

      const files: SelectedAudioFile[] = [];
      for (const uri of documentSelectResult) {
        try {
          const fileInfo = await this.getFileInfo(uri);
          files.push(fileInfo);
        } catch (e) {
          console.error(`获取文件信息失败: ${uri}`, e);
        }
      }

      return files;
    } catch (error) {
      console.error('多选音频文件失败:', error);
      throw new Error(`多选音频文件失败: ${error}`);
    }
  }
  
  /**
   * 选择图片文件（用于更换专辑封面）
   * @returns 选中的图片URI
   */
  async selectImageFile(): Promise<string | null> {
    try {
      let photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;

      let photoPicker = new photoAccessHelper.PhotoViewPicker();
      
      const photoSelectResult = await photoPicker.select(photoSelectOptions);
      
      if (!photoSelectResult || photoSelectResult.photoUris.length === 0) {
        return null;
      }
      
      return photoSelectResult.photoUris[0];
    } catch (error) {
      console.error('选择图片文件失败:', error);
      throw new Error(`选择图片文件失败: ${error}`);
    }
  }
  
  /**
   * 获取文件详细信息
   */
  private async getFileInfo(uri: string): Promise<SelectedAudioFile> {
    try {
      // 获取文件stat信息
      const stat = fileIo.statSync(uri);
      
      // 提取文件名
      const fileName = this.extractFileName(uri);
      
      return {
        uri: uri,
        fileName: fileName,
        fileSize: stat.size
      };
    } catch (error) {
      console.error('获取文件信息失败:', error);
      // 返回基本信息
      return {
        uri: uri,
        fileName: this.extractFileName(uri),
        fileSize: 0
      };
    }
  }
  
  /**
   * 从URI提取文件名
   */
  private extractFileName(uri: string): string {
    // URI格式通常是: file://.../filename.mp3
    const parts = uri.split('/');
    const lastPart = parts[parts.length - 1] || 'Unknown';
    
    // 可能需要解码URL编码
    try {
      return decodeURIComponent(lastPart);
    } catch {
      return lastPart;
    }
  }
  
  /**
   * 打开文件获取文件描述符
   * @param uri 文件URI
   * @returns 文件描述符
   */
  async openFileDescriptor(uri: string): Promise<number> {
    try {
      const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      return file.fd;
    } catch (error) {
      console.error('打开文件失败:', error);
      throw new Error(`打开文件失败: ${error}`);
    }
  }
  
  /**
   * 关闭文件描述符
   * @param fd 文件描述符
   */
  async closeFileDescriptor(fd: number): Promise<void> {
    try {
      await fileIo.close(fd);
    } catch (error) {
      console.error('关闭文件失败:', error);
    }
  }
}
