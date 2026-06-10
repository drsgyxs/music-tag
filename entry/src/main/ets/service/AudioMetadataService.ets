/**
 * 音频元数据服务
 * 负责读取和处理音频文件的元数据
 */
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { AudioMetadata, AudioMetadataBuilder } from '../model/AudioMetadata';
import { Id3v2Reader, Id3TagData } from './Id3v2Reader';
import { FlacReader } from './FlacReader';
import { M4aReader } from './M4aReader';

interface LyricLine {
  time: number;
  text: string;
}

export class AudioMetadataService {
  private static instance: AudioMetadataService;
  
  private constructor() {}
  
  static getInstance(): AudioMetadataService {
    if (!AudioMetadataService.instance) {
      AudioMetadataService.instance = new AudioMetadataService();
    }
    return AudioMetadataService.instance;
  }
  
  /**
   * 从文件URI读取音频元数据
   * @param fileUri 文件URI（从AudioViewPicker获取）
   * @returns 音频元数据对象
   */
  async readMetadataFromUri(fileUri: string): Promise<AudioMetadata> {
    let fd: number = -1;

    try {
      const file = fileIo.openSync(fileUri, fileIo.OpenMode.READ_ONLY);
      fd = file.fd;

      const metadata = await this.buildMetadataFromFd(fd, fileUri);

      // 获取文件大小
      try {
        const stat = fileIo.statSync(fileUri);
        metadata.fileSize = stat.size;
      } catch (e) {
        console.error('获取文件大小失败:', e);
      }

      return metadata;
    } catch (error) {
      console.error('读取音频元数据失败:', error);
      throw new Error(`读取音频元数据失败: ${error}`);
    } finally {
      if (fd >= 0) {
        try {
          fileIo.closeSync(fd);
        } catch (e) {
          console.error('关闭文件失败:', e);
        }
      }
    }
  }
  
  /**
   * 从文件描述符读取音频元数据
   * @param fd 文件描述符
   * @param filePath 文件路径（用于记录）
   * @returns 音频元数据对象
   */
  async readMetadataFromFd(fd: number, filePath: string): Promise<AudioMetadata> {
    try {
      return await this.buildMetadataFromFd(fd, filePath);
    } catch (error) {
      console.error('从FD读取音频元数据失败:', error);
      throw new Error(`从FD读取音频元数据失败: ${error}`);
    }
  }

  /**
   * 核心读取流程：
   * 1. 用自研 Id3v2Reader 解析 ID3v2 标签（含歌词、封面、全部文本帧）；
   * 2. 再用 AVMetadataExtractor 补充时长，并在无 ID3v2 标签时回退基础字段。
   */
  private async buildMetadataFromFd(fd: number, filePath: string): Promise<AudioMetadata> {
    const fileName = this.extractFileName(filePath);
    const fileFormat = this.extractFileFormat(filePath);

    // 1. 按格式解析标签：FLAC 走 Vorbis Comment，M4A 走 MP4 ilst，其余按 ID3v2 解析
    let id3: Id3TagData;
    if (fileFormat === 'flac') {
      id3 = this.readFlacMetaFromFd(fd);
    } else if (fileFormat === 'm4a' || fileFormat === 'mp4' || fileFormat === 'aac') {
      id3 = this.readM4aMetaFromFd(fd);
    } else {
      id3 = this.readId3TagFromFd(fd);
    }
    const metadata = AudioMetadataBuilder.fromId3(id3, filePath, fileName);
    metadata.fileFormat = fileFormat;

    // 2. AVMetadataExtractor 补充时长 / 无标签时回退
    let avMetadataExtractor: media.AVMetadataExtractor | null = null;
    try {
      avMetadataExtractor = await media.createAVMetadataExtractor();
      avMetadataExtractor.fdSrc = { fd: fd, offset: 0, length: -1 };
      const av = await avMetadataExtractor.fetchMetadata();

      if (av.duration) {
        metadata.duration = Number(av.duration);
      }

      // 文件不含 ID3v2 标签时（如仅 ID3v1），用系统 API 回退填充基础字段
      if (!id3.hasTag) {
        metadata.title = metadata.title || av.title || '';
        metadata.artist = metadata.artist || av.artist || '';
        metadata.album = metadata.album || av.album || '';
        metadata.albumArtist = metadata.albumArtist || av.albumArtist || '';
        metadata.composer = metadata.composer || av.composer || '';
        metadata.genre = metadata.genre || av.genre || '';
      }

      // 仅当 ID3 中无内嵌封面时，回退用系统 API 取封面
      if (!id3.coverData) {
        try {
          const coverPixelMap = await avMetadataExtractor.fetchAlbumCover();
          if (coverPixelMap) {
            metadata.coverImage = coverPixelMap;
            metadata.hasCover = true;
          }
        } catch (e) {
          console.info('获取专辑封面失败或无封面:', e);
        }
      }
    } catch (e) {
      console.info('AVMetadataExtractor 补充信息失败:', e);
    } finally {
      if (avMetadataExtractor) {
        try {
          await avMetadataExtractor.release();
        } catch (e) {
          console.error('释放AVMetadataExtractor失败:', e);
        }
      }
    }

    // 3. 将 ID3 内嵌封面解码为 PixelMap
    if (id3.coverData) {
      try {
        metadata.coverImage = await this.arrayBufferToPixelMap(id3.coverData);
        metadata.hasCover = true;
      } catch (e) {
        console.error('ID3 封面解码失败:', e);
      }
    }

    return metadata;
  }

  /**
   * 仅读取文件头部的 ID3v2 标签区域并解析，避免读入整个音频文件。
   */
  private readId3TagFromFd(fd: number): Id3TagData {
    try {
      const headerBuf = new ArrayBuffer(10);
      const got = fileIo.readSync(fd, headerBuf, { offset: 0, length: 10 });
      const h = new Uint8Array(headerBuf);
      if (got < 10 || h[0] !== 0x49 || h[1] !== 0x44 || h[2] !== 0x33) {
        return Id3v2Reader.readTag(h.subarray(0, got)); // 无 ID3v2，返回空结果
      }

      const flags = h[5];
      const size =
        ((h[6] & 0x7F) << 21) | ((h[7] & 0x7F) << 14) | ((h[8] & 0x7F) << 7) | (h[9] & 0x7F);
      let total = 10 + size;
      if ((flags & 0x10) !== 0) {
        total += 10; // footer
      }

      const tagBuf = new ArrayBuffer(total);
      const read = fileIo.readSync(fd, tagBuf, { offset: 0, length: total });
      return Id3v2Reader.readTag(new Uint8Array(tagBuf, 0, read));
    } catch (e) {
      console.error('读取 ID3v2 标签失败:', e);
      return Id3v2Reader.readTag(new Uint8Array(0));
    }
  }

  /**
   * 逐块读取 FLAC 文件头部的元数据区（不读入音频数据），再交由 FlacReader 解析。
   */
  private readFlacMetaFromFd(fd: number): Id3TagData {
    try {
      const magicBuf = new ArrayBuffer(4);
      const got = fileIo.readSync(fd, magicBuf, { offset: 0, length: 4 });
      const magic = new Uint8Array(magicBuf);
      if (got < 4 || magic[0] !== 0x66 || magic[1] !== 0x4C || magic[2] !== 0x61 || magic[3] !== 0x43) {
        return FlacReader.readTag(new Uint8Array(0)); // 非 FLAC
      }

      const chunks: Uint8Array[] = [];
      chunks.push(new Uint8Array([0x66, 0x4C, 0x61, 0x43]));

      let pos = 4;
      let last = false;
      while (!last) {
        const headerBuf = new ArrayBuffer(4);
        const hr = fileIo.readSync(fd, headerBuf, { offset: pos, length: 4 });
        if (hr < 4) {
          break;
        }
        const h = new Uint8Array(headerBuf);
        last = (h[0] & 0x80) !== 0;
        const len = (h[1] << 16) | (h[2] << 8) | h[3];

        chunks.push(h);
        if (len > 0) {
          const blockBuf = new ArrayBuffer(len);
          const br = fileIo.readSync(fd, blockBuf, { offset: pos + 4, length: len });
          chunks.push(new Uint8Array(blockBuf, 0, br));
          if (br < len) {
            break;
          }
        }
        pos += 4 + len;
      }

      let total = 0;
      for (const c of chunks) {
        total += c.length;
      }
      const all = new Uint8Array(total);
      let o = 0;
      for (const c of chunks) {
        all.set(c, o);
        o += c.length;
      }
      return FlacReader.readTag(all);
    } catch (e) {
      console.error('读取 FLAC 元数据失败:', e);
      return FlacReader.readTag(new Uint8Array(0));
    }
  }

  /**
   * 遍历 M4A 顶层盒子定位 moov，整块读入后交由 M4aReader 解析。
   */
  private readM4aMetaFromFd(fd: number): Id3TagData {
    try {
      const fileSize: number = fileIo.statSync(fd).size;
      let off = 0;
      while (off + 8 <= fileSize) {
        const headerBuf = new ArrayBuffer(16);
        const hr = fileIo.readSync(fd, headerBuf, { offset: off, length: 16 });
        if (hr < 8) {
          break;
        }
        const h = new Uint8Array(headerBuf);
        let size = (h[0] << 24 | h[1] << 16 | h[2] << 8 | h[3]) >>> 0;
        const type = String.fromCharCode(h[4], h[5], h[6], h[7]);
        if (size === 1) {
          // 64 位 largesize（仅取低 53 位足够覆盖实际文件大小）
          const hi = (h[8] << 24 | h[9] << 16 | h[10] << 8 | h[11]) >>> 0;
          const lo = (h[12] << 24 | h[13] << 16 | h[14] << 8 | h[15]) >>> 0;
          size = hi * 0x100000000 + lo;
        } else if (size === 0) {
          size = fileSize - off;
        }
        if (size < 8) {
          break;
        }

        if (type === 'moov') {
          const moovBuf = new ArrayBuffer(size);
          const mr = fileIo.readSync(fd, moovBuf, { offset: off, length: size });
          return M4aReader.readTag(new Uint8Array(moovBuf, 0, mr));
        }
        off += size;
      }
      return M4aReader.readTag(new Uint8Array(0));
    } catch (e) {
      console.error('读取 M4A 元数据失败:', e);
      return M4aReader.readTag(new Uint8Array(0));
    }
  }
  
  /**
   * 从PixelMap创建图片源并编码为JPEG格式的ArrayBuffer
   * @param pixelMap 图片像素图
   * @returns ArrayBuffer格式的图片数据
   */
  async pixelMapToArrayBuffer(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
    try {
      const imagePackerApi = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: 90
      };
      const data = await imagePackerApi.packToData(pixelMap, packOpts);
      await imagePackerApi.release();
      return data;
    } catch (error) {
      console.error('PixelMap转ArrayBuffer失败:', error);
      throw new Error(`PixelMap转ArrayBuffer失败${error}}`);
    }
  }
  
  /**
   * 从ArrayBuffer创建PixelMap
   * @param buffer 图片数据
   * @returns PixelMap对象
   */
  async arrayBufferToPixelMap(buffer: ArrayBuffer): Promise<image.PixelMap> {
    try {
      const imageSource = image.createImageSource(buffer);
      const pixelMap = await imageSource.createPixelMap();
      await imageSource.release();
      return pixelMap;
    } catch (error) {
      console.error('ArrayBuffer转PixelMap失败:', error);
      throw new Error(`ArrayBuffer转PixelMap失败: ${error}}`);
    }
  }
  
  /**
   * 从文件路径加载封面图片
   * @param imagePath 图片文件路径
   * @returns PixelMap对象
   */
  async loadCoverImage(imagePath: string): Promise<image.PixelMap | null> {
    try {
      const imageSource = image.createImageSource(imagePath);
      const pixelMap = await imageSource.createPixelMap();
      await imageSource.release();
      return pixelMap;
    } catch (error) {
      console.error('加载封面图片失败:', error);
      return null;
    }
  }
  
  /**
   * 解析LRC格式歌词
   * @param lrcContent LRC歌词内容
   * @returns 解析后的歌词数组，每项包含时间和文本
   */
  parseLrcLyrics(lrcContent: string): Array<LyricLine> {
    const lyrics: Array<LyricLine> = [];
    const lines = lrcContent.split('\n');
    
    const timeRegex = /\[(\d{2}):(\d{2})\.(\d{2,3})\]/;
    
    for (const line of lines) {
      const match = line.match(timeRegex);
      if (match) {
        const minutes = parseInt(match[1]);
        const seconds = parseInt(match[2]);
        const milliseconds = parseInt(match[3].padEnd(3, '0'));
        const time = minutes * 60 * 1000 + seconds * 1000 + milliseconds;
        
        const text = line.replace(timeRegex, '').trim();
        if (text) {
          lyrics.push({ time, text });
        }
      }
    }
    
    // 按时间排序
    lyrics.sort((a, b) => a.time - b.time);
    
    return lyrics;
  }
  
  /**
   * 格式化时长显示
   * @param durationMs 时长（毫秒）
   * @returns 格式化的时长字符串（mm:ss）
   */
  formatDuration(durationMs: number): string {
    if (!durationMs || durationMs <= 0) {
      return '00:00';
    }
    
    const totalSeconds = Math.floor(durationMs / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }
  
  /**
   * 格式化文件大小显示
   * @param bytes 字节数
   * @returns 格式化的文件大小字符串
   */
  formatFileSize(bytes: number): string {
    if (!bytes || bytes <= 0) {
      return '0 B';
    }
    
    const units = ['B', 'KB', 'MB', 'GB'];
    let unitIndex = 0;
    let size = bytes;
    
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    
    return `${size.toFixed(2)} ${units[unitIndex]}`;
  }
  
  /**
   * 从URI中提取文件名
   */
  private extractFileName(uri: string): string {
    const parts = uri.split('/');
    return parts[parts.length - 1] || 'Unknown';
  }
  
  /**
   * 从URI中提取文件格式
   */
  private extractFileFormat(uri: string): string {
    const fileName = this.extractFileName(uri);
    const parts = fileName.split('.');
    return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : 'unknown';
  }
}
