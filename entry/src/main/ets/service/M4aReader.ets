/**
 * M4A / MP4 元数据解析器（纯 ArkTS 实现）
 *
 * M4A 采用 ISO BMFF（MP4）盒子结构，iTunes 风格标签位于 moov.udta.meta.ilst 中。
 * 每个标签是一个 atom（如 ©nam），内部含一个 data 盒子：
 *   data: size(4) + 'data'(4) + 类型标志(4) + locale(4) + 值
 * 类型标志：1 = UTF-8 文本，13 = JPEG，14 = PNG，0 = 二进制（如 trkn/disk）。
 *
 * 本类输入为完整的 moov 盒子字节，输出与 ID3 一致的 Id3TagData。
 */

import { Id3TagData } from './Id3v2Reader';

interface BoxRange {
  start: number;
  contentStart: number;
  end: number;
}

export class M4aReader {
  /**
   * 解析 moov 盒子字节，提取标签
   * @param moov 完整的 moov 盒子（从 size 字段开始）
   */
  static readTag(moov: Uint8Array): Id3TagData {
    const data: Id3TagData = M4aReader.empty();
    if (moov.length < 8 || M4aReader.readAscii(moov, 4, 4) !== 'moov') {
      return data;
    }

    const udta = M4aReader.findBox(moov, 8, moov.length, 'udta');
    if (!udta) {
      return data;
    }
    const meta = M4aReader.findBox(moov, udta.contentStart, udta.end, 'meta');
    if (!meta) {
      return data;
    }
    // meta 通常是 FullBox（含 4 字节版本/标志），需探测其子盒子起点
    const metaChildStart = M4aReader.metaChildrenStart(moov, meta);
    const ilst = M4aReader.findBox(moov, metaChildStart, meta.end, 'ilst');
    if (!ilst) {
      return data;
    }

    M4aReader.parseIlst(moov, ilst.contentStart, ilst.end, data);
    data.hasTag = true;
    return data;
  }

  // ===================== ilst 遍历 =====================

  private static parseIlst(buf: Uint8Array, start: number, end: number, data: Id3TagData): void {
    let off: number = start;
    while (off + 8 <= end) {
      const size: number = M4aReader.readU32BE(buf, off);
      if (size < 8 || off + size > end) {
        break;
      }
      const name: string = M4aReader.readAscii(buf, off + 4, 4);
      const itemEnd: number = off + size;

      const dataBox = M4aReader.findBox(buf, off + 8, itemEnd, 'data');
      if (dataBox) {
        M4aReader.handleItem(name, buf, dataBox.contentStart, dataBox.end, data);
      }
      off = itemEnd;
    }
  }

  /** data 盒子内容：类型标志(4) + locale(4) + 值 */
  private static handleItem(name: string, buf: Uint8Array, start: number, end: number, data: Id3TagData): void {
    if (start + 8 > end) {
      return;
    }
    const indicator: number = M4aReader.readU32BE(buf, start);
    const valueStart: number = start + 8; // 跳过类型标志 + locale
    const value: Uint8Array = buf.subarray(valueStart, end);

    if (name === 'covr') {
      if (value.length > 0) {
        data.coverData = M4aReader.toArrayBuffer(value);
        data.coverMime = M4aReader.coverMime(indicator, value);
      }
      return;
    }

    if (name === 'trkn' || name === 'disk') {
      const num: string = M4aReader.parseNumberPair(value);
      if (num.length > 0) {
        if (name === 'trkn') {
          data.trackNumber = num;
        } else {
          data.discNumber = num;
        }
      }
      return;
    }

    const text: string = M4aReader.decodeUtf8(value).trim();
    if (text.length === 0) {
      return;
    }
    switch (name) {
      case '©nam': data.title = text; break;
      case '©ART': data.artist = text; break;
      case '©alb': data.album = text; break;
      case 'aART': data.albumArtist = text; break;
      case '©wrt': data.composer = text; break;
      case '©day': data.year = text.substring(0, 4); break;
      case '©gen': data.genre = text; break;
      case '©cmt': data.comment = text; break;
      case '©lyr': data.lyrics = text; break;
      case 'cprt': data.copyright = text; break;
      default: break;
    }
  }

  /** trkn/disk 值为二进制：保留字节(2) + 序号(2,BE) + 总数(2,BE) + 保留(2) */
  private static parseNumberPair(value: Uint8Array): string {
    if (value.length < 4) {
      return '';
    }
    const index: number = (value[2] << 8) | value[3];
    if (index <= 0) {
      return '';
    }
    if (value.length >= 6) {
      const total: number = (value[4] << 8) | value[5];
      if (total > 0) {
        return `${index}/${total}`;
      }
    }
    return `${index}`;
  }

  private static coverMime(indicator: number, value: Uint8Array): string {
    if (indicator === 14) {
      return 'image/png';
    }
    if (indicator === 13) {
      return 'image/jpeg';
    }
    // 按字节签名嗅探
    if (value.length >= 4 && value[0] === 0x89 && value[1] === 0x50) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  // ===================== 盒子工具 =====================

  /** meta 作为 FullBox 时其子盒子前有 4 字节版本/标志；若探测失败则按无版本/标志处理 */
  private static metaChildrenStart(buf: Uint8Array, meta: BoxRange): number {
    const withVf: number = meta.contentStart + 4;
    if (M4aReader.looksLikeBox(buf, withVf, meta.end)) {
      return withVf;
    }
    if (M4aReader.looksLikeBox(buf, meta.contentStart, meta.end)) {
      return meta.contentStart;
    }
    return withVf;
  }

  private static looksLikeBox(buf: Uint8Array, off: number, end: number): boolean {
    if (off + 8 > end) {
      return false;
    }
    const size: number = M4aReader.readU32BE(buf, off);
    if (size < 8 || off + size > end) {
      return false;
    }
    for (let i = 4; i < 8; i++) {
      const c: number = buf[off + i];
      const printable: boolean = (c >= 0x20 && c < 0x7F) || c === 0xA9;
      if (!printable) {
        return false;
      }
    }
    return true;
  }

  /** 在 [start, end) 内查找首个指定类型的盒子 */
  private static findBox(buf: Uint8Array, start: number, end: number, type: string): BoxRange | null {
    let off: number = start;
    while (off + 8 <= end) {
      const size: number = M4aReader.readU32BE(buf, off);
      if (size < 8) {
        break;
      }
      const boxEnd: number = Math.min(off + size, end);
      const t: string = M4aReader.readAscii(buf, off + 4, 4);
      if (t === type) {
        return { start: off, contentStart: off + 8, end: boxEnd };
      }
      off += size;
    }
    return null;
  }

  private static readU32BE(bytes: Uint8Array, pos: number): number {
    return ((bytes[pos] << 24) | (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | (bytes[pos + 3])) >>> 0;
  }

  private static readAscii(bytes: Uint8Array, from: number, len: number): string {
    let s: string = '';
    for (let i = 0; i < len; i++) {
      s += String.fromCharCode(bytes[from + i]);
    }
    return s;
  }

  private static decodeUtf8(bytes: Uint8Array): string {
    let s: string = '';
    let i: number = 0;
    const n: number = bytes.length;
    while (i < n) {
      const c: number = bytes[i++];
      if (c < 0x80) {
        s += String.fromCharCode(c);
      } else if (c < 0xE0 && i < n) {
        const c2: number = bytes[i++];
        s += String.fromCharCode(((c & 0x1F) << 6) | (c2 & 0x3F));
      } else if (c < 0xF0 && i + 1 < n) {
        const c2: number = bytes[i++];
        const c3: number = bytes[i++];
        s += String.fromCharCode(((c & 0x0F) << 12) | ((c2 & 0x3F) << 6) | (c3 & 0x3F));
      } else if (i + 2 < n) {
        const c2: number = bytes[i++];
        const c3: number = bytes[i++];
        const c4: number = bytes[i++];
        let cp: number = ((c & 0x07) << 18) | ((c2 & 0x3F) << 12) | ((c3 & 0x3F) << 6) | (c4 & 0x3F);
        cp -= 0x10000;
        s += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
      } else {
        break;
      }
    }
    return s;
  }

  private static toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    const copy = new Uint8Array(bytes.length);
    copy.set(bytes, 0);
    return copy.buffer;
  }

  private static empty(): Id3TagData {
    return {
      title: '',
      artist: '',
      album: '',
      albumArtist: '',
      composer: '',
      writer: '',
      year: '',
      genre: '',
      trackNumber: '',
      discNumber: '',
      comment: '',
      copyright: '',
      lyrics: '',
      coverData: null,
      coverMime: '',
      hasTag: false
    };
  }
}
