/**
 * ID3v2 标签解析器（纯 ArkTS 实现）
 *
 * HarmonyOS 的 AVMetadataExtractor 读取元数据并不完整（例如读不到内嵌歌词 USLT，
 * 也读不到 lyricist / copyright 等帧）。本类直接按 ID3v2 规范解析 MP3 头部的标签字节，
 * 支持 v2.2 / v2.3 / v2.4 三个版本、四种文本编码、标签级 unsynchronisation，
 * 从而把歌词、封面以及全部文本帧完整读出。
 */

export interface Id3TagData {
  title: string;
  artist: string;
  album: string;
  albumArtist: string;
  composer: string;
  writer: string;       // 作词 (TEXT / TXT)
  year: string;
  genre: string;
  trackNumber: string;
  discNumber: string;
  comment: string;
  copyright: string;
  lyrics: string;       // 内嵌歌词 (USLT / ULT)
  coverData: ArrayBuffer | null;
  coverMime: string;
  hasTag: boolean;      // 是否检测到 ID3v2 标签
}

export class Id3v2Reader {
  /**
   * 解析 ID3v2 标签字节（应至少包含完整标签区域）
   */
  static readTag(content: Uint8Array): Id3TagData {
    const data: Id3TagData = Id3v2Reader.empty();
    if (content.length < 10) {
      return data;
    }
    if (content[0] !== 0x49 || content[1] !== 0x44 || content[2] !== 0x33) {
      return data; // 非 "ID3"
    }

    const major: number = content[3];
    const flags: number = content[5];
    const size: number =
      ((content[6] & 0x7F) << 21) |
      ((content[7] & 0x7F) << 14) |
      ((content[8] & 0x7F) << 7) |
      (content[9] & 0x7F);

    const declaredEnd: number = Math.min(10 + size, content.length);
    let frameArea: Uint8Array = content.subarray(10, declaredEnd);

    // 标签级 unsynchronisation（flag bit7）：还原 FF 00 -> FF
    if ((flags & 0x80) !== 0) {
      frameArea = Id3v2Reader.deUnsynchronise(frameArea);
    }

    // 扩展头（flag bit6）：跳过
    let start: number = 0;
    if ((flags & 0x40) !== 0) {
      start = Id3v2Reader.skipExtendedHeader(frameArea, major);
    }

    data.hasTag = true;
    Id3v2Reader.parseFrames(frameArea, start, major, data);
    return data;
  }

  // ===================== 帧遍历 =====================

  private static parseFrames(buf: Uint8Array, start: number, major: number, data: Id3TagData): void {
    const idLen: number = major === 2 ? 3 : 4;
    const sizeLen: number = major === 2 ? 3 : 4;
    const flagLen: number = major === 2 ? 0 : 2;
    const headerLen: number = idLen + sizeLen + flagLen;
    const end: number = buf.length;

    let off: number = start;
    while (off + headerLen <= end) {
      if (buf[off] === 0) {
        break; // 进入 padding 区
      }
      const id: string = Id3v2Reader.readAscii(buf, off, idLen);

      let frameSize: number;
      if (major === 2) {
        frameSize = (buf[off + 3] << 16) | (buf[off + 4] << 8) | buf[off + 5];
      } else if (major === 4) {
        // v2.4 帧大小为 synchsafe
        frameSize =
          ((buf[off + 4] & 0x7F) << 21) |
          ((buf[off + 5] & 0x7F) << 14) |
          ((buf[off + 6] & 0x7F) << 7) |
          (buf[off + 7] & 0x7F);
      } else {
        // v2.3 帧大小为普通大端
        frameSize =
          (buf[off + 4] << 24) | (buf[off + 5] << 16) | (buf[off + 6] << 8) | buf[off + 7];
      }

      const bodyStart: number = off + headerLen;
      if (frameSize <= 0 || bodyStart + frameSize > end) {
        break; // 大小异常，停止解析
      }

      const body: Uint8Array = buf.subarray(bodyStart, bodyStart + frameSize);
      Id3v2Reader.handleFrame(id, body, data);
      off = bodyStart + frameSize;
    }
  }

  private static handleFrame(rawId: string, body: Uint8Array, data: Id3TagData): void {
    if (body.length === 0) {
      return;
    }
    const id: string = Id3v2Reader.canonicalId(rawId);

    if (id === 'APIC') {
      Id3v2Reader.parseApic(body, data);
      return;
    }
    if (id === 'PIC') {
      Id3v2Reader.parsePicV22(body, data);
      return;
    }
    if (id === 'COMM') {
      const text: string = Id3v2Reader.parseDescribedText(body);
      if (text.length > 0) {
        data.comment = text;
      }
      return;
    }
    if (id === 'USLT') {
      const text: string = Id3v2Reader.parseDescribedText(body);
      if (text.length > 0) {
        data.lyrics = text;
      }
      return;
    }
    if (id.charAt(0) === 'T') {
      const enc: number = body[0];
      const text: string = Id3v2Reader.decodeText(enc, body.subarray(1));
      Id3v2Reader.assignTextField(id, text, data);
    }
  }

  private static assignTextField(id: string, text: string, data: Id3TagData): void {
    const value: string = text.trim();
    if (value.length === 0) {
      return;
    }
    switch (id) {
      case 'TIT2': data.title = value; break;
      case 'TPE1': data.artist = value; break;
      case 'TALB': data.album = value; break;
      case 'TPE2': data.albumArtist = value; break;
      case 'TCOM': data.composer = value; break;
      case 'TEXT': data.writer = value; break;
      case 'TYER': data.year = value; break;
      case 'TDRC': data.year = value.substring(0, 4); break; // v2.4 录制时间
      case 'TCON': data.genre = Id3v2Reader.cleanGenre(value); break;
      case 'TRCK': data.trackNumber = value; break;
      case 'TPOS': data.discNumber = value; break;
      case 'TCOP': data.copyright = value; break;
      default: break;
    }
  }

  // ===================== COMM / USLT：跳过描述符取正文 =====================

  /** 结构：encoding(1) + language(3) + 描述符(以终止符结束) + 正文 */
  private static parseDescribedText(body: Uint8Array): string {
    const enc: number = body[0];
    const textStart: number = Id3v2Reader.skipTerminatedString(body, enc, 4);
    return Id3v2Reader.decodeText(enc, body.subarray(textStart));
  }

  // ===================== 封面 =====================

  /** v2.3/v2.4 APIC：encoding + MIME(latin1,0终止) + 类型 + 描述 + 图片 */
  private static parseApic(body: Uint8Array, data: Id3TagData): void {
    const enc: number = body[0];
    let i: number = 1;
    const mimeStart: number = i;
    while (i < body.length && body[i] !== 0) {
      i++;
    }
    const mime: string = Id3v2Reader.decodeLatin1(body.subarray(mimeStart, i));
    i++; // 跳过 MIME 终止符
    i++; // 跳过图片类型字节
    i = Id3v2Reader.skipTerminatedString(body, enc, i); // 跳过描述
    if (i < body.length) {
      data.coverData = Id3v2Reader.toArrayBuffer(body.subarray(i));
      data.coverMime = mime.length > 0 ? mime : 'image/jpeg';
    }
  }

  /** v2.2 PIC：encoding + 图片格式(3字符) + 类型 + 描述 + 图片 */
  private static parsePicV22(body: Uint8Array, data: Id3TagData): void {
    const enc: number = body[0];
    let i: number = 1 + 3; // 跳过 3 字符图片格式
    i++; // 跳过图片类型字节
    i = Id3v2Reader.skipTerminatedString(body, enc, i);
    if (i < body.length) {
      data.coverData = Id3v2Reader.toArrayBuffer(body.subarray(i));
      data.coverMime = 'image/jpeg';
    }
  }

  // ===================== 文本解码 =====================

  private static decodeText(enc: number, bytes: Uint8Array): string {
    let s: string;
    if (enc === 1) {
      s = Id3v2Reader.decodeUtf16(bytes, true);
    } else if (enc === 2) {
      s = Id3v2Reader.decodeUtf16(bytes, false);
    } else if (enc === 3) {
      s = Id3v2Reader.decodeUtf8(bytes);
    } else {
      s = Id3v2Reader.decodeLatin1(bytes);
    }
    // 去除尾部 NUL 终止符与首部 BOM 字符
    return Id3v2Reader.stripPadding(s);
  }

  /** 去除解码后字符串首部 BOM(U+FEFF) 与尾部 NUL(U+0000) 终止符 */
  private static stripPadding(s: string): string {
    let start: number = 0;
    let end: number = s.length;
    if (end > start && s.charCodeAt(start) === 0xFEFF) {
      start++;
    }
    while (end > start && s.charCodeAt(end - 1) === 0x0000) {
      end--;
    }
    return s.substring(start, end);
  }

  private static decodeLatin1(bytes: Uint8Array): string {
    let s: string = '';
    for (let i = 0; i < bytes.length; i++) {
      s += String.fromCharCode(bytes[i]);
    }
    return s;
  }

  private static decodeUtf16(bytes: Uint8Array, defaultLE: boolean): string {
    let i: number = 0;
    let le: boolean = defaultLE;
    if (bytes.length >= 2) {
      if (bytes[0] === 0xFF && bytes[1] === 0xFE) {
        le = true;
        i = 2;
      } else if (bytes[0] === 0xFE && bytes[1] === 0xFF) {
        le = false;
        i = 2;
      }
    }
    let s: string = '';
    for (; i + 1 < bytes.length; i += 2) {
      const u: number = le ? (bytes[i] | (bytes[i + 1] << 8)) : ((bytes[i] << 8) | bytes[i + 1]);
      s += String.fromCharCode(u);
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

  // ===================== 工具 =====================

  /** 返回终止符之后的索引；UTF-16(enc 1/2)用 00 00，其余用单 00 */
  private static skipTerminatedString(bytes: Uint8Array, enc: number, from: number): number {
    if (enc === 1 || enc === 2) {
      let j: number = from;
      while (j + 1 < bytes.length) {
        if (bytes[j] === 0 && bytes[j + 1] === 0) {
          return j + 2;
        }
        j += 2;
      }
      return bytes.length;
    }
    let j: number = from;
    while (j < bytes.length) {
      if (bytes[j] === 0) {
        return j + 1;
      }
      j++;
    }
    return bytes.length;
  }

  private static readAscii(bytes: Uint8Array, from: number, len: number): string {
    let s: string = '';
    for (let i = 0; i < len; i++) {
      s += String.fromCharCode(bytes[from + i]);
    }
    return s;
  }

  /** 还原 unsynchronisation：FF 00 -> FF */
  private static deUnsynchronise(bytes: Uint8Array): Uint8Array {
    const out: number[] = [];
    for (let i = 0; i < bytes.length; i++) {
      out.push(bytes[i]);
      if (bytes[i] === 0xFF && i + 1 < bytes.length && bytes[i + 1] === 0x00) {
        i++; // 跳过填充的 00
      }
    }
    return new Uint8Array(out);
  }

  private static skipExtendedHeader(buf: Uint8Array, major: number): number {
    if (buf.length < 4) {
      return 0;
    }
    if (major === 4) {
      // v2.4：扩展头大小为 synchsafe，且包含自身这 4 字节
      const sz: number =
        ((buf[0] & 0x7F) << 21) | ((buf[1] & 0x7F) << 14) | ((buf[2] & 0x7F) << 7) | (buf[3] & 0x7F);
      return sz <= buf.length ? sz : 0;
    }
    // v2.3：扩展头大小为普通大端，不含这 4 字节
    const sz: number = (buf[0] << 24) | (buf[1] << 16) | (buf[2] << 8) | buf[3];
    const total: number = 4 + sz;
    return total <= buf.length ? total : 0;
  }

  private static cleanGenre(value: string): string {
    // 形如 "(13)" 的纯数字引用去掉括号，其余原样返回
    const m = value.match(/^\((\d+)\)$/);
    return m ? m[1] : value;
  }

  private static canonicalId(id: string): string {
    switch (id) {
      case 'TT2': return 'TIT2';
      case 'TP1': return 'TPE1';
      case 'TAL': return 'TALB';
      case 'TP2': return 'TPE2';
      case 'TCM': return 'TCOM';
      case 'TXT': return 'TEXT';
      case 'TYE': return 'TYER';
      case 'TCO': return 'TCON';
      case 'TRK': return 'TRCK';
      case 'TPA': return 'TPOS';
      case 'TCR': return 'TCOP';
      case 'COM': return 'COMM';
      case 'ULT': return 'USLT';
      case 'PIC': return 'PIC';
      default: return id;
    }
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
