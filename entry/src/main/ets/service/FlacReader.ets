/**
 * FLAC 元数据解析器（纯 ArkTS 实现）
 *
 * FLAC 不使用 ID3，而是在文件头部的 "fLaC" 标识之后排布一系列元数据块。
 * 标签信息位于 VORBIS_COMMENT 块（block type 4），封面位于 PICTURE 块（block type 6）。
 * 本类解析这两类块，输出与 ID3 读取一致的 Id3TagData 结构，便于上层统一处理。
 *
 * 块结构：
 * - 文件标识："fLaC"（4 字节）
 * - 每个块：1 字节(bit7=最后一块标志, bit0-6=块类型) + 3 字节块长度(大端) + 块数据
 * - VORBIS_COMMENT 内部长度字段为小端；PICTURE 内部长度字段为大端
 */

import { Id3TagData } from './Id3v2Reader';

const BLOCK_VORBIS_COMMENT: number = 4;
const BLOCK_PICTURE: number = 6;
const PIC_TYPE_FRONT_COVER: number = 3;

export class FlacReader {
  /**
   * 解析 FLAC 元数据区字节（需从 "fLaC" 标识开始，至少包含完整元数据块链）
   */
  static readTag(content: Uint8Array): Id3TagData {
    const data: Id3TagData = FlacReader.empty();
    if (content.length < 4) {
      return data;
    }
    // "fLaC"
    if (content[0] !== 0x66 || content[1] !== 0x4C || content[2] !== 0x61 || content[3] !== 0x43) {
      return data;
    }

    let off: number = 4;
    let last: boolean = false;
    while (!last && off + 4 <= content.length) {
      const header: number = content[off];
      last = (header & 0x80) !== 0;
      const type: number = header & 0x7F;
      const len: number = (content[off + 1] << 16) | (content[off + 2] << 8) | content[off + 3];
      const bodyStart: number = off + 4;
      const blockEnd: number = bodyStart + len;
      if (blockEnd > content.length) {
        break;
      }

      const body: Uint8Array = content.subarray(bodyStart, blockEnd);
      if (type === BLOCK_VORBIS_COMMENT) {
        FlacReader.parseVorbisComment(body, data);
        data.hasTag = true;
      } else if (type === BLOCK_PICTURE) {
        FlacReader.parsePicture(body, data);
      }

      off = blockEnd;
    }

    return data;
  }

  // ===================== VORBIS_COMMENT =====================

  /** 结构：vendorLen(4,LE) + vendor + count(4,LE) + [ commentLen(4,LE) + "KEY=value" ] * count */
  private static parseVorbisComment(body: Uint8Array, data: Id3TagData): void {
    let pos: number = 0;
    if (pos + 4 > body.length) {
      return;
    }
    const vendorLen: number = FlacReader.readUint32LE(body, pos);
    pos += 4 + vendorLen; // 跳过 vendor 字符串
    if (pos + 4 > body.length) {
      return;
    }
    const count: number = FlacReader.readUint32LE(body, pos);
    pos += 4;

    for (let i = 0; i < count; i++) {
      if (pos + 4 > body.length) {
        break;
      }
      const len: number = FlacReader.readUint32LE(body, pos);
      pos += 4;
      if (len < 0 || pos + len > body.length) {
        break;
      }
      const comment: string = FlacReader.decodeUtf8(body.subarray(pos, pos + len));
      pos += len;
      FlacReader.assignComment(comment, data);
    }
  }

  /** 将 "KEY=value" 注释项映射到对应字段（KEY 不区分大小写） */
  private static assignComment(comment: string, data: Id3TagData): void {
    const eq: number = comment.indexOf('=');
    if (eq < 0) {
      return;
    }
    const key: string = comment.substring(0, eq).toUpperCase();
    const value: string = comment.substring(eq + 1).trim();
    if (value.length === 0) {
      return;
    }

    switch (key) {
      case 'TITLE': data.title = value; break;
      case 'ARTIST': data.artist = value; break;
      case 'ALBUM': data.album = value; break;
      case 'ALBUMARTIST':
      case 'ALBUM ARTIST': data.albumArtist = value; break;
      case 'COMPOSER': data.composer = value; break;
      case 'LYRICIST': data.writer = value; break;
      case 'DATE':
      case 'YEAR': data.year = value.substring(0, 4); break;
      case 'GENRE': data.genre = value; break;
      case 'TRACKNUMBER': data.trackNumber = value; break;
      case 'DISCNUMBER': data.discNumber = value; break;
      case 'COMMENT':
      case 'DESCRIPTION': data.comment = value; break;
      case 'COPYRIGHT': data.copyright = value; break;
      case 'LYRICS':
      case 'UNSYNCEDLYRICS': data.lyrics = value; break;
      default: break;
    }
  }

  // ===================== PICTURE =====================

  /**
   * PICTURE 块（字段均为大端）：
   * 图片类型(4) + MIME长度(4) + MIME + 描述长度(4) + 描述 +
   * 宽(4) + 高(4) + 色深(4) + 颜色数(4) + 图片数据长度(4) + 图片数据
   */
  private static parsePicture(body: Uint8Array, data: Id3TagData): void {
    let pos: number = 0;
    if (pos + 4 > body.length) {
      return;
    }
    const picType: number = FlacReader.readUint32BE(body, pos);
    pos += 4;

    if (pos + 4 > body.length) {
      return;
    }
    const mimeLen: number = FlacReader.readUint32BE(body, pos);
    pos += 4;
    if (pos + mimeLen > body.length) {
      return;
    }
    const mime: string = FlacReader.decodeLatin1(body.subarray(pos, pos + mimeLen));
    pos += mimeLen;

    if (pos + 4 > body.length) {
      return;
    }
    const descLen: number = FlacReader.readUint32BE(body, pos);
    pos += 4 + descLen; // 跳过描述

    pos += 16; // 跳过 宽/高/色深/颜色数 各 4 字节
    if (pos + 4 > body.length) {
      return;
    }
    const dataLen: number = FlacReader.readUint32BE(body, pos);
    pos += 4;
    if (dataLen <= 0 || pos + dataLen > body.length) {
      return;
    }

    // 优先采用前封面（type 3）；若已存在则仅在遇到前封面时覆盖
    if (data.coverData === null || picType === PIC_TYPE_FRONT_COVER) {
      data.coverData = FlacReader.toArrayBuffer(body.subarray(pos, pos + dataLen));
      data.coverMime = mime.length > 0 ? mime : 'image/jpeg';
    }
  }

  // ===================== 字节工具 =====================

  private static readUint32LE(bytes: Uint8Array, pos: number): number {
    return ((bytes[pos]) | (bytes[pos + 1] << 8) | (bytes[pos + 2] << 16) | (bytes[pos + 3] << 24)) >>> 0;
  }

  private static readUint32BE(bytes: Uint8Array, pos: number): number {
    return ((bytes[pos] << 24) | (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | (bytes[pos + 3])) >>> 0;
  }

  private static decodeLatin1(bytes: Uint8Array): string {
    let s: string = '';
    for (let i = 0; i < bytes.length; i++) {
      s += String.fromCharCode(bytes[i]);
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
