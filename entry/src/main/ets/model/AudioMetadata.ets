/**
 * 音频元数据模型
 * 用于存储音频文件的标签信息
 */
import { image } from '@kit.ImageKit';
import { Id3TagData } from '../service/Id3v2Reader';

export interface AudioMetadata {
  // 基础信息
  title: string;           // 歌曲标题
  artist: string;          // 艺术家
  album: string;           // 专辑名称
  albumArtist: string;     // 专辑艺术家
  composer: string;        // 作曲家
  writer: string;          // 词作者

  // 时间信息
  year: string;            // 发行年份
  duration: number;        // 时长（毫秒）
  trackNumber: string;     // 音轨号
  discNumber: string;      // 光盘号

  // 其他信息
  genre: string;           // 音乐类型
  comment: string;         // 注释
  copyright: string;       // 版权信息

  // 封面和歌词
  coverImage: image.PixelMap | null;  // 专辑封面（运行时使用，不序列化）
  coverImagePath: string;             // 封面图片路径
  lyrics: string;                     // 内嵌歌词

  // 文件信息
  filePath: string;        // 文件路径
  fileName: string;        // 文件名
  fileSize: number;        // 文件大小（字节）
  fileFormat: string;      // 文件格式（mp3, flac, wav等）

  // 元数据完整性标记
  hasCover: boolean;       // 是否有封面
  hasLyrics: boolean;      // 是否有歌词
}

/**
 * 音频元数据构建器
 * 提供默认值和构建方法
 */
export class AudioMetadataBuilder {
  static createDefault(): AudioMetadata {
    return {
      title: '',
      artist: '',
      album: '',
      albumArtist: '',
      composer: '',
      writer: '',
      year: '',
      duration: 0,
      trackNumber: '',
      discNumber: '',
      genre: '',
      comment: '',
      copyright: '',
      coverImage: null,
      coverImagePath: '',
      lyrics: '',
      filePath: '',
      fileName: '',
      fileSize: 0,
      fileFormat: '',
      hasCover: false,
      hasLyrics: false
    };
  }

  /**
   * 从自研 ID3v2 解析结果构建 AudioMetadata。
   * 相比 AVMetadataExtractor，可额外读出歌词(USLT)、作词(TEXT)、版权(TCOP) 等字段。
   */
  static fromId3(data: Id3TagData, filePath: string, fileName: string): AudioMetadata {
    const metadata = AudioMetadataBuilder.createDefault();

    metadata.title = data.title;
    metadata.artist = data.artist;
    metadata.album = data.album;
    metadata.albumArtist = data.albumArtist;
    metadata.composer = data.composer;
    metadata.writer = data.writer;
    metadata.year = data.year;
    metadata.genre = data.genre;
    metadata.trackNumber = data.trackNumber;
    metadata.discNumber = data.discNumber;
    metadata.comment = data.comment;
    metadata.copyright = data.copyright;
    metadata.lyrics = data.lyrics;
    metadata.hasLyrics = data.lyrics.length > 0;

    metadata.filePath = filePath;
    metadata.fileName = fileName;

    return metadata;
  }
}
