/**
 * 已导入音频文件列表项模型
 *
 * 主页文件列表中每个条目对应一个用户导入的音频文件。
 * uri 来自 DocumentViewPicker，并通过 fileShare 做持久化授权，
 * 以便 App 重启后仍可长期访问与回写该文件。
 */

export interface AudioFileEntry {
  uri: string;          // 文件 URI（已持久化读写权限）
  fileName: string;     // 文件名（含扩展名）
  fileFormat: string;   // 文件格式（mp3 / flac / m4a 等，小写）
  fileSize: number;     // 文件大小（字节）
  addedTime: number;    // 导入时间戳（毫秒）
}

export class AudioFileEntryHelper {
  /** 从 URI 提取文件名（已解码） */
  static extractFileName(uri: string): string {
    const parts: string[] = uri.split('/');
    const last: string = parts[parts.length - 1] || 'Unknown';
    try {
      return decodeURIComponent(last);
    } catch (e) {
      return last;
    }
  }

  /** 从文件名提取小写扩展名 */
  static extractFormat(fileName: string): string {
    const parts: string[] = fileName.split('.');
    return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : 'unknown';
  }

  /** 序列化为 JSON 字符串（用于 Preferences 存储） */
  static stringify(list: AudioFileEntry[]): string {
    return JSON.stringify(list);
  }

  /** 从 JSON 字符串反序列化；非法内容返回空数组 */
  static parse(json: string): AudioFileEntry[] {
    if (!json || json.length === 0) {
      return [];
    }
    try {
      const arr = JSON.parse(json) as AudioFileEntry[];
      return Array.isArray(arr) ? arr : [];
    } catch (e) {
      return [];
    }
  }
}
