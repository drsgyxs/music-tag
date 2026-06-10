/**
 * FLAC 标签写入器（纯 ArkTS 实现）
 *
 * FLAC 的标签写回不能像 MP3 那样简单地在音频前拼接一段标签，而要重建文件头部的
 * 元数据块链：保留 STREAMINFO 等必要块，丢弃旧的 VORBIS_COMMENT / PICTURE / PADDING，
 * 再追加由本类新生成的 VORBIS_COMMENT 块与 PICTURE 块，最后拼回原始音频帧。
 *
 * 注意：
 * - 块头为 1 字节标志/类型 + 3 字节大端长度；最后一个元数据块需置 bit7 标志。
 * - VORBIS_COMMENT 内部长度字段为小端，PICTURE 内部长度字段为大端。
 */

import { Id3TagInput } from './Id3v2Writer';

const BLOCK_STREAMINFO: number = 0;
const BLOCK_APPLICATION: number = 2;
const BLOCK_SEEKTABLE: number = 3;
const BLOCK_VORBIS_COMMENT: number = 4;
const BLOCK_CUESHEET: number = 5;
const BLOCK_PICTURE: number = 6;
const PIC_TYPE_FRONT_COVER: number = 3;

const VENDOR: string = 'HarmonyOS AudioTagEditor';

export class FlacWriter {
  /**
   * 用新的标签内容重建整个 FLAC 文件字节
   * @param content 原始文件完整字节（需以 "fLaC" 开头）
   * @param input 标签内容
   */
  static rewrite(content: Uint8Array, input: Id3TagInput): Uint8Array {
    if (content.length < 4 ||
      content[0] !== 0x66 || content[1] !== 0x4C || content[2] !== 0x61 || content[3] !== 0x43) {
      throw new Error('不是有效的 FLAC 文件');
    }

    // 遍历元数据块：保留必要块，定位音频起始偏移
    const preserved: Uint8Array[] = [];
    let off: number = 4;
    let audioStart: number = -1;
    while (off + 4 <= content.length) {
      const header: number = content[off];
      const last: boolean = (header & 0x80) !== 0;
      const type: number = header & 0x7F;
      const len: number = (content[off + 1] << 16) | (content[off + 2] << 8) | content[off + 3];
      const bodyStart: number = off + 4;
      const blockEnd: number = bodyStart + len;
      if (blockEnd > content.length) {
        throw new Error('FLAC 元数据块越界，文件可能已损坏');
      }

      // 保留 STREAMINFO / APPLICATION / SEEKTABLE / CUESHEET；
      // 丢弃 VORBIS_COMMENT(4) / PICTURE(6) / PADDING(1)（由本类重新生成）
      if (type === BLOCK_STREAMINFO || type === BLOCK_APPLICATION ||
        type === BLOCK_SEEKTABLE || type === BLOCK_CUESHEET) {
        preserved.push(content.subarray(off, blockEnd));
      }

      off = blockEnd;
      if (last) {
        audioStart = off;
        break;
      }
    }

    if (audioStart < 0) {
      throw new Error('FLAC 元数据结构异常，未找到音频起始位置');
    }

    // 组装新的元数据块链
    const blocks: Uint8Array[] = [];
    for (const b of preserved) {
      const copy = new Uint8Array(b.length);
      copy.set(b, 0);
      copy[0] = copy[0] & 0x7F; // 先清除“最后一块”标志，稍后统一在末块设置
      blocks.push(copy);
    }
    blocks.push(FlacWriter.buildVorbisCommentBlock(input));
    if (input.coverData && input.coverData.byteLength > 0) {
      blocks.push(FlacWriter.buildPictureBlock(input.coverData, input.coverMime));
    }
    // 末块置“最后一块”标志
    const lastBlock = blocks[blocks.length - 1];
    lastBlock[0] = lastBlock[0] | 0x80;

    // 拼接：fLaC + 元数据块 + 原始音频
    let metaLen: number = 0;
    for (const b of blocks) {
      metaLen += b.length;
    }
    const audio: Uint8Array = content.subarray(audioStart);
    const out = new Uint8Array(4 + metaLen + audio.length);
    out[0] = 0x66; out[1] = 0x4C; out[2] = 0x61; out[3] = 0x43;
    let p: number = 4;
    for (const b of blocks) {
      out.set(b, p);
      p += b.length;
    }
    out.set(audio, p);
    return out;
  }

  // ===================== 块构造 =====================

  /** 构造 VORBIS_COMMENT 块（块头 + 块体） */
  private static buildVorbisCommentBlock(input: Id3TagInput): Uint8Array {
    const comments: string[] = [];
    FlacWriter.addComment(comments, 'TITLE', input.title);
    FlacWriter.addComment(comments, 'ARTIST', input.artist);
    FlacWriter.addComment(comments, 'ALBUM', input.album);
    FlacWriter.addComment(comments, 'ALBUMARTIST', input.albumArtist);
    FlacWriter.addComment(comments, 'COMPOSER', input.composer);
    FlacWriter.addComment(comments, 'LYRICIST', input.writer);
    FlacWriter.addComment(comments, 'DATE', input.year);
    FlacWriter.addComment(comments, 'GENRE', input.genre);
    FlacWriter.addComment(comments, 'TRACKNUMBER', input.trackNumber);
    FlacWriter.addComment(comments, 'DISCNUMBER', input.discNumber);
    FlacWriter.addComment(comments, 'COMMENT', input.comment);
    FlacWriter.addComment(comments, 'COPYRIGHT', input.copyright);
    FlacWriter.addComment(comments, 'LYRICS', input.lyrics);

    const body: number[] = [];
    const vendorBytes: number[] = FlacWriter.utf8Encode(VENDOR);
    FlacWriter.pushUint32LE(body, vendorBytes.length);
    FlacWriter.appendAll(body, vendorBytes);
    FlacWriter.pushUint32LE(body, comments.length);
    for (const c of comments) {
      const cb: number[] = FlacWriter.utf8Encode(c);
      FlacWriter.pushUint32LE(body, cb.length);
      FlacWriter.appendAll(body, cb);
    }

    return FlacWriter.wrapBlock(BLOCK_VORBIS_COMMENT, body);
  }

  /** 构造 PICTURE 块（块头 + 块体） */
  private static buildPictureBlock(coverData: ArrayBuffer, coverMime?: string): Uint8Array {
    const mime: string = coverMime && coverMime.length > 0 ? coverMime : 'image/jpeg';
    const mimeBytes: number[] = FlacWriter.asciiEncode(mime);
    const picBytes = new Uint8Array(coverData);

    const body: number[] = [];
    FlacWriter.pushUint32BE(body, PIC_TYPE_FRONT_COVER); // 图片类型：前封面
    FlacWriter.pushUint32BE(body, mimeBytes.length);
    FlacWriter.appendAll(body, mimeBytes);
    FlacWriter.pushUint32BE(body, 0); // 描述长度（无描述）
    FlacWriter.pushUint32BE(body, 0); // 宽（未知）
    FlacWriter.pushUint32BE(body, 0); // 高（未知）
    FlacWriter.pushUint32BE(body, 0); // 色深（未知）
    FlacWriter.pushUint32BE(body, 0); // 颜色数（非索引色为 0）
    FlacWriter.pushUint32BE(body, picBytes.length);
    for (let i = 0; i < picBytes.length; i++) {
      body.push(picBytes[i]);
    }

    return FlacWriter.wrapBlock(BLOCK_PICTURE, body);
  }

  /** 给块体加上 1 字节类型 + 3 字节大端长度的块头 */
  private static wrapBlock(type: number, body: number[]): Uint8Array {
    const len: number = body.length;
    const block = new Uint8Array(4 + len);
    block[0] = type & 0x7F; // 最后一块标志稍后统一设置
    block[1] = (len >> 16) & 0xFF;
    block[2] = (len >> 8) & 0xFF;
    block[3] = len & 0xFF;
    block.set(body, 4);
    return block;
  }

  private static addComment(list: string[], key: string, value?: string): void {
    if (value && value.length > 0) {
      list.push(`${key}=${value}`);
    }
  }

  // ===================== 字节工具 =====================

  private static pushUint32LE(buf: number[], n: number): void {
    buf.push(n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF, (n >> 24) & 0xFF);
  }

  private static pushUint32BE(buf: number[], n: number): void {
    buf.push((n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF);
  }

  private static appendAll(buf: number[], bytes: number[]): void {
    for (let i = 0; i < bytes.length; i++) {
      buf.push(bytes[i]);
    }
  }

  private static asciiEncode(str: string): number[] {
    const out: number[] = [];
    for (let i = 0; i < str.length; i++) {
      out.push(str.charCodeAt(i) & 0xFF);
    }
    return out;
  }

  /** 将字符串编码为 UTF-8 字节（正确处理中文与代理对） */
  private static utf8Encode(str: string): number[] {
    const out: number[] = [];
    for (let i = 0; i < str.length; i++) {
      let code: number = str.charCodeAt(i);
      if (code >= 0xD800 && code <= 0xDBFF && i + 1 < str.length) {
        const next: number = str.charCodeAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          code = 0x10000 + ((code - 0xD800) << 10) + (next - 0xDC00);
          i++;
        }
      }
      if (code < 0x80) {
        out.push(code);
      } else if (code < 0x800) {
        out.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
      } else if (code < 0x10000) {
        out.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
      } else {
        out.push(
          0xF0 | (code >> 18),
          0x80 | ((code >> 12) & 0x3F),
          0x80 | ((code >> 6) & 0x3F),
          0x80 | (code & 0x3F)
        );
      }
    }
    return out;
  }
}
