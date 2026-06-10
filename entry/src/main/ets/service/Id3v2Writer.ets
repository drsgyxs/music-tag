/**
 * ID3v2.3 标签二进制编码器（纯 ArkTS 实现）
 *
 * HarmonyOS 的 MediaKit 只提供读取元数据的 API，无法写回文件。
 * 本类不依赖任何系统写 API，直接按 ID3v2.3 规范构造标签的二进制字节，
 * 由调用方将其拼接到 MP3 音频帧之前并写回文件，从而实现真正的标签写入。
 *
 * 规范要点（ID3v2.3.0）：
 * - 标签头 10 字节："ID3" + 版本(03 00) + flags(00) + synchsafe 长度(4 字节)
 * - 帧头 10 字节：帧ID(4) + 大小(4, 普通大端) + flags(2)
 * - 文本帧采用编码字节 0x01 + UTF-16(带 BOM)，以完整支持中文
 */

export interface Id3TagInput {
  title?: string;
  artist?: string;
  album?: string;
  albumArtist?: string;
  composer?: string;
  writer?: string;           // 词作者 (TEXT)
  year?: string;
  genre?: string;
  trackNumber?: string;
  discNumber?: string;
  comment?: string;
  copyright?: string;        // 版权 (TCOP)
  lyrics?: string;
  coverData?: ArrayBuffer;   // 封面图片原始字节（JPEG/PNG）
  coverMime?: string;        // 封面 MIME，如 image/jpeg
}

const TEXT_ENCODING_UTF16: number = 0x01;   // UTF-16 with BOM
const TEXT_ENCODING_LATIN1: number = 0x00;  // ISO-8859-1
const PIC_TYPE_FRONT_COVER: number = 0x03;

export class Id3v2Writer {
  /**
   * 根据输入构造完整的 ID3v2.3 标签字节
   */
  static buildTag(input: Id3TagInput): Uint8Array {
    const frames: number[] = [];

    Id3v2Writer.appendTextFrame(frames, 'TIT2', input.title);
    Id3v2Writer.appendTextFrame(frames, 'TPE1', input.artist);
    Id3v2Writer.appendTextFrame(frames, 'TALB', input.album);
    Id3v2Writer.appendTextFrame(frames, 'TPE2', input.albumArtist);
    Id3v2Writer.appendTextFrame(frames, 'TCOM', input.composer);
    Id3v2Writer.appendTextFrame(frames, 'TEXT', input.writer);
    Id3v2Writer.appendTextFrame(frames, 'TYER', input.year);
    Id3v2Writer.appendTextFrame(frames, 'TCON', input.genre);
    Id3v2Writer.appendTextFrame(frames, 'TRCK', input.trackNumber);
    Id3v2Writer.appendTextFrame(frames, 'TPOS', input.discNumber);
    Id3v2Writer.appendTextFrame(frames, 'TCOP', input.copyright);
    Id3v2Writer.appendCommentFrame(frames, input.comment);
    Id3v2Writer.appendLyricsFrame(frames, input.lyrics);
    Id3v2Writer.appendApicFrame(frames, input.coverData, input.coverMime);

    const tagSize: number = frames.length;
    const header: number[] = [];
    header.push(0x49, 0x44, 0x33);     // "ID3"
    header.push(0x03, 0x00);           // version 2.3.0
    header.push(0x00);                 // flags
    Id3v2Writer.pushSynchsafe(header, tagSize);

    const out = new Uint8Array(header.length + frames.length);
    out.set(header, 0);
    out.set(frames, header.length);
    return out;
  }

  // ===================== 帧构造 =====================

  /** 文本帧：encoding(0x01) + UTF-16(BOM) 文本 + 终止符 */
  private static appendTextFrame(frames: number[], frameId: string, value?: string): void {
    if (!value || value.length === 0) {
      return;
    }
    const data: number[] = [];
    data.push(TEXT_ENCODING_UTF16);
    Id3v2Writer.pushUtf16WithBom(data, value);
    data.push(0x00, 0x00); // UTF-16 字符串终止符
    Id3v2Writer.appendFrame(frames, frameId, data);
  }

  /** COMM 注释帧：encoding + 语言码 + 空描述 + 文本 */
  private static appendCommentFrame(frames: number[], value?: string): void {
    if (!value || value.length === 0) {
      return;
    }
    const data: number[] = [];
    data.push(TEXT_ENCODING_UTF16);
    data.push(0x58, 0x58, 0x58); // 语言 "XXX"
    Id3v2Writer.pushEmptyUtf16(data); // 空描述（BOM + 终止符）
    Id3v2Writer.pushUtf16WithBom(data, value);
    data.push(0x00, 0x00);
    Id3v2Writer.appendFrame(frames, 'COMM', data);
  }

  /** USLT 非同步歌词帧：encoding + 语言码 + 空描述 + 歌词 */
  private static appendLyricsFrame(frames: number[], value?: string): void {
    if (!value || value.length === 0) {
      return;
    }
    const data: number[] = [];
    data.push(TEXT_ENCODING_UTF16);
    data.push(0x58, 0x58, 0x58); // 语言 "XXX"
    Id3v2Writer.pushEmptyUtf16(data); // 空内容描述符
    Id3v2Writer.pushUtf16WithBom(data, value);
    data.push(0x00, 0x00);
    Id3v2Writer.appendFrame(frames, 'USLT', data);
  }

  /** APIC 封面帧：encoding + MIME + 图片类型 + 空描述 + 图片字节 */
  private static appendApicFrame(frames: number[], coverData?: ArrayBuffer, coverMime?: string): void {
    if (!coverData || coverData.byteLength === 0) {
      return;
    }
    const mime: string = coverMime && coverMime.length > 0 ? coverMime : 'image/jpeg';
    const data: number[] = [];
    data.push(TEXT_ENCODING_LATIN1);        // 描述文本编码：ISO-8859-1
    Id3v2Writer.pushAscii(data, mime);
    data.push(0x00);                         // MIME 终止符
    data.push(PIC_TYPE_FRONT_COVER);         // 图片类型：封面（前）
    data.push(0x00);                         // 空描述（ISO-8859-1 单字节终止符）

    const imageBytes = new Uint8Array(coverData);
    for (let i = 0; i < imageBytes.length; i++) {
      data.push(imageBytes[i]);
    }
    Id3v2Writer.appendFrame(frames, 'APIC', data);
  }

  /** 写入一个完整帧（帧头 10 字节 + 数据） */
  private static appendFrame(frames: number[], frameId: string, data: number[]): void {
    Id3v2Writer.pushAscii(frames, frameId);  // 帧ID 4 字节
    Id3v2Writer.pushUint32BE(frames, data.length); // 大小（v2.3 普通大端，非 synchsafe）
    frames.push(0x00, 0x00);                 // flags
    for (let i = 0; i < data.length; i++) {
      frames.push(data[i]);
    }
  }

  // ===================== 字节工具 =====================

  /** 追加 UTF-16LE 字节（带 FF FE BOM），可正确编码中文及代理对 */
  private static pushUtf16WithBom(buf: number[], str: string): void {
    buf.push(0xFF, 0xFE); // little-endian BOM
    for (let i = 0; i < str.length; i++) {
      const code = str.charCodeAt(i);
      buf.push(code & 0xFF, (code >> 8) & 0xFF);
    }
  }

  /** 空 UTF-16 字符串：BOM + 终止符 */
  private static pushEmptyUtf16(buf: number[]): void {
    buf.push(0xFF, 0xFE, 0x00, 0x00);
  }

  /** 追加 ASCII 字节（仅取低 8 位） */
  private static pushAscii(buf: number[], str: string): void {
    for (let i = 0; i < str.length; i++) {
      buf.push(str.charCodeAt(i) & 0xFF);
    }
  }

  /** 32 位大端整数 */
  private static pushUint32BE(buf: number[], n: number): void {
    buf.push((n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF);
  }

  /** synchsafe 整数：每字节仅用低 7 位 */
  private static pushSynchsafe(buf: number[], n: number): void {
    buf.push((n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F);
  }
}
