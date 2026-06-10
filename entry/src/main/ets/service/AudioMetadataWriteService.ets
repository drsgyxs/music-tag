/**
 * 音乐标签写入服务
 *
 * 由于 HarmonyOS 没有官方写入元数据的 API，本服务通过 CoreFileKit 的 fileIo
 * 直接对文件做二进制重写后原地覆盖写回：
 * - MP3：剥离旧 ID3v2 标签，拼接 Id3v2Writer 生成的新 ID3v2.3 标签；
 * - FLAC：由 FlacWriter 重建头部的元数据块链（Vorbis Comment + Picture）；
 * - M4A：由 M4aWriter 重建 moov.udta.meta.ilst 并修正块偏移表。
 */

import { fileIo } from '@kit.CoreFileKit';
import { Id3v2Writer, Id3TagInput } from './Id3v2Writer';
import { FlacWriter } from './FlacWriter';
import { M4aWriter } from './M4aWriter';

export class AudioMetadataWriteService {
  private static instance: AudioMetadataWriteService;

  private constructor() {}

  static getInstance(): AudioMetadataWriteService {
    if (!AudioMetadataWriteService.instance) {
      AudioMetadataWriteService.instance = new AudioMetadataWriteService();
    }
    return AudioMetadataWriteService.instance;
  }

  /**
   * 将标签原地写入音频文件（按格式分派 MP3 / FLAC）
   * @param uri 文件 URI（来自文档选择器，需具备读写权限）
   * @param format 文件格式（mp3 / flac）
   * @param input 标签内容
   */
  async writeTags(uri: string, format: string, input: Id3TagInput): Promise<void> {
    const fmt: string = format.toLowerCase();
    const isM4a: boolean = fmt === 'm4a' || fmt === 'mp4' || fmt === 'aac';
    if (fmt !== 'mp3' && fmt !== 'flac' && !isM4a) {
      throw new Error(`暂不支持写入 ${format} 格式，请使用导出功能`);
    }

    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE);
      const fd: number = file.fd;

      // 读取整个文件
      const stat = fileIo.statSync(fd);
      const fileSize: number = stat.size;
      const readBuffer = new ArrayBuffer(fileSize);
      const bytesRead: number = fileIo.readSync(fd, readBuffer, { offset: 0, length: fileSize });
      const content = new Uint8Array(readBuffer, 0, bytesRead);

      // 按格式重建文件字节
      const newContent: Uint8Array = fmt === 'flac'
        ? FlacWriter.rewrite(content, input)
        : isM4a ? M4aWriter.rewrite(content, input) : AudioMetadataWriteService.buildMp3Content(content, input);

      // 原地覆盖写回：先截断再从头写入
      fileIo.truncateSync(fd, 0);
      fileIo.writeSync(fd, newContent.buffer, { offset: 0, length: newContent.length });
      fileIo.fsyncSync(fd);
    } catch (error) {
      console.error('写入标签失败:', error);
      throw new Error(
        `写入标签失败（可能是所选文件未授予写权限，建议改用文档选择器选取本地存储中的文件）: ${error}`
      );
    } finally {
      if (file) {
        try {
          fileIo.closeSync(file);
        } catch (e) {
          console.error('关闭文件失败:', e);
        }
      }
    }
  }

  /** MP3：剥离旧 ID3v2 标签并拼接新标签 */
  private static buildMp3Content(content: Uint8Array, input: Id3TagInput): Uint8Array {
    const audioStart: number = AudioMetadataWriteService.getExistingTagSize(content);
    const audioBytes = content.subarray(audioStart);

    const newTag: Uint8Array = Id3v2Writer.buildTag(input);
    const newContent = new Uint8Array(newTag.length + audioBytes.length);
    newContent.set(newTag, 0);
    newContent.set(audioBytes, newTag.length);
    return newContent;
  }

  /**
   * 解析文件头部是否存在 ID3v2 标签，返回其占用的总字节数（即音频起始偏移）。
   * 不存在则返回 0。
   */
  private static getExistingTagSize(content: Uint8Array): number {
    if (content.length < 10) {
      return 0;
    }
    // "ID3"
    if (content[0] !== 0x49 || content[1] !== 0x44 || content[2] !== 0x33) {
      return 0;
    }
    const flags: number = content[5];
    // synchsafe 长度（每字节低 7 位）
    const size: number =
      ((content[6] & 0x7F) << 21) |
      ((content[7] & 0x7F) << 14) |
      ((content[8] & 0x7F) << 7) |
      (content[9] & 0x7F);

    let total: number = 10 + size;
    // footer 标志位（bit 4）存在时再加 10 字节
    if ((flags & 0x10) !== 0) {
      total += 10;
    }
    return total <= content.length ? total : 0;
  }
}
