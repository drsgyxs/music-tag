/**
 * M4A / MP4 标签写入器（纯 ArkTS 实现）
 *
 * 写回 iTunes 风格标签需要重建 moov.udta.meta.ilst：
 *   1. 保留 moov 内除 udta 外的全部内容（尤其 trak/sample 表）；
 *   2. 用新的标签重建 ilst，并重组 meta / udta / moov，更新各级盒子大小；
 *   3. 关键：若 moov 位于 mdat（音频数据）之前，moov 体积变化会使 mdat 整体平移，
 *      此时必须把 stco / co64 中所有绝对块偏移按 delta 修正，否则音频无法正确播放。
 *
 * 盒子结构：size(4,大端) + type(4) + 内容。meta 为 FullBox（含 4 字节版本/标志）。
 */

import { Id3TagInput } from './Id3v2Writer';

interface BoxRange {
  start: number;
  contentStart: number;
  end: number;
}

const DATA_TYPE_TEXT: number = 1;
const DATA_TYPE_JPEG: number = 13;
const DATA_TYPE_PNG: number = 14;

export class M4aWriter {
  /**
   * 用新标签重建整个 M4A 文件字节
   * @param content 原始文件完整字节
   * @param input 标签内容
   */
  static rewrite(content: Uint8Array, input: Id3TagInput): Uint8Array {
    // 顶层扫描：定位 moov 与 mdat
    let off: number = 0;
    const n: number = content.length;
    let moovStart: number = -1;
    let moovSize: number = -1;
    let mdatStart: number = -1;
    while (off + 8 <= n) {
      let size: number = M4aWriter.readU32BE(content, off);
      const type: string = M4aWriter.readAscii(content, off + 4, 4);
      if (size === 1) {
        size = M4aWriter.readU64BE(content, off + 8); // 64 位 largesize
      } else if (size === 0) {
        size = n - off; // 延伸至文件结尾
      }
      if (size < 8) {
        break;
      }
      if (type === 'moov') {
        moovStart = off;
        moovSize = size;
      } else if (type === 'mdat' && mdatStart < 0) {
        mdatStart = off;
      }
      off += size;
    }

    if (moovStart < 0 || moovSize < 8) {
      throw new Error('未找到 moov 盒子，文件可能不是有效的 M4A');
    }

    const moov: Uint8Array = content.subarray(moovStart, moovStart + moovSize);
    const newMoov: Uint8Array = M4aWriter.rebuildMoov(moov, input);
    const delta: number = newMoov.length - moov.length;

    // moov 在 mdat 之前时，修正块偏移表
    if (mdatStart >= 0 && moovStart < mdatStart && delta !== 0) {
      M4aWriter.patchChunkOffsets(newMoov, delta);
    }

    // 重组：moov 之前 + 新 moov + moov 之后
    const out = new Uint8Array(content.length + delta);
    out.set(content.subarray(0, moovStart), 0);
    out.set(newMoov, moovStart);
    out.set(content.subarray(moovStart + moovSize), moovStart + newMoov.length);
    return out;
  }

  // ===================== moov / udta / meta 重建 =====================

  private static rebuildMoov(moov: Uint8Array, input: Id3TagInput): Uint8Array {
    const udta = M4aWriter.findBox(moov, 8, moov.length, 'udta');
    const newUdta: Uint8Array = M4aWriter.rebuildUdta(udta ? moov.subarray(udta.start, udta.end) : null, input);

    let children: Uint8Array;
    if (udta) {
      children = M4aWriter.concat([
        moov.subarray(8, udta.start),
        newUdta,
        moov.subarray(udta.end)
      ]);
    } else {
      children = M4aWriter.concat([moov.subarray(8), newUdta]);
    }
    return M4aWriter.makeBox('moov', children);
  }

  private static rebuildUdta(udta: Uint8Array | null, input: Id3TagInput): Uint8Array {
    let metaBytes: Uint8Array | null = null;
    let before: Uint8Array = new Uint8Array(0);
    let after: Uint8Array = new Uint8Array(0);

    if (udta) {
      const meta = M4aWriter.findBox(udta, 8, udta.length, 'meta');
      if (meta) {
        metaBytes = udta.subarray(meta.start, meta.end);
        before = udta.subarray(8, meta.start);
        after = udta.subarray(meta.end);
      } else {
        before = udta.subarray(8);
      }
    }

    const newMeta: Uint8Array = M4aWriter.rebuildMeta(metaBytes, input);
    const children: Uint8Array = M4aWriter.concat([before, newMeta, after]);
    return M4aWriter.makeBox('udta', children);
  }

  private static rebuildMeta(meta: Uint8Array | null, input: Id3TagInput): Uint8Array {
    const newIlst: Uint8Array = M4aWriter.buildIlst(input);
    const preserved: Uint8Array[] = [];
    let hasHdlr: boolean = false;

    if (meta) {
      // meta 内容起点：FullBox 的 4 字节版本/标志之后
      const childStart: number = M4aWriter.metaChildrenStart(meta);
      let off: number = childStart;
      while (off + 8 <= meta.length) {
        const size: number = M4aWriter.readU32BE(meta, off);
        if (size < 8 || off + size > meta.length) {
          break;
        }
        const type: string = M4aWriter.readAscii(meta, off + 4, 4);
        if (type === 'hdlr') {
          hasHdlr = true;
          preserved.push(meta.subarray(off, off + size));
        } else if (type !== 'ilst') {
          preserved.push(meta.subarray(off, off + size)); // 保留 ilst 之外的子盒子
        }
        off += size;
      }
    }

    const parts: Uint8Array[] = [];
    parts.push(new Uint8Array([0x00, 0x00, 0x00, 0x00])); // 版本/标志
    if (!hasHdlr) {
      parts.push(M4aWriter.buildMetaHdlr()); // 缺省时补一个元数据 hdlr
    }
    for (const p of preserved) {
      parts.push(p);
    }
    parts.push(newIlst);
    return M4aWriter.makeBox('meta', M4aWriter.concat(parts));
  }

  /** 缺省的元数据 handler 盒子（handler_type = 'mdir'） */
  private static buildMetaHdlr(): Uint8Array {
    const body: number[] = [];
    M4aWriter.pushU32BE(body, 0);            // 版本/标志
    M4aWriter.pushU32BE(body, 0);            // pre_defined
    M4aWriter.pushAscii(body, 'mdir');       // handler_type
    M4aWriter.pushAscii(body, 'appl');       // reserved[0]
    M4aWriter.pushU32BE(body, 0);            // reserved[1]
    M4aWriter.pushU32BE(body, 0);            // reserved[2]
    body.push(0x00);                          // 空名称（null 结尾）
    return M4aWriter.makeBox('hdlr', M4aWriter.toBytes(body));
  }

  // ===================== ilst 构造 =====================

  private static buildIlst(input: Id3TagInput): Uint8Array {
    const items: Uint8Array[] = [];
    M4aWriter.addText(items, '©nam', input.title);
    M4aWriter.addText(items, '©ART', input.artist);
    M4aWriter.addText(items, '©alb', input.album);
    M4aWriter.addText(items, 'aART', input.albumArtist);
    M4aWriter.addText(items, '©wrt', input.composer);
    M4aWriter.addText(items, '©day', input.year);
    M4aWriter.addText(items, '©gen', input.genre);
    M4aWriter.addText(items, '©cmt', input.comment);
    M4aWriter.addText(items, 'cprt', input.copyright);
    M4aWriter.addText(items, '©lyr', input.lyrics);
    M4aWriter.addNumberPair(items, 'trkn', input.trackNumber);
    M4aWriter.addNumberPair(items, 'disk', input.discNumber);
    M4aWriter.addCover(items, input.coverData, input.coverMime);

    return M4aWriter.makeBox('ilst', M4aWriter.concat(items));
  }

  private static addText(items: Uint8Array[], name: string, value?: string): void {
    if (!value || value.length === 0) {
      return;
    }
    const dataBox: Uint8Array = M4aWriter.makeDataBox(DATA_TYPE_TEXT, M4aWriter.toBytes(M4aWriter.utf8Encode(value)));
    items.push(M4aWriter.makeBox(name, dataBox));
  }

  /** trkn/disk：解析 "3" 或 "3/12"，写为 8 字节二进制值 */
  private static addNumberPair(items: Uint8Array[], name: string, value?: string): void {
    if (!value || value.length === 0) {
      return;
    }
    const parts: string[] = value.split('/');
    const index: number = M4aWriter.parseInt(parts[0]);
    if (index <= 0) {
      return;
    }
    const total: number = parts.length > 1 ? M4aWriter.parseInt(parts[1]) : 0;
    const v = new Uint8Array(8);
    v[2] = (index >> 8) & 0xFF;
    v[3] = index & 0xFF;
    v[4] = (total >> 8) & 0xFF;
    v[5] = total & 0xFF;
    const dataBox: Uint8Array = M4aWriter.makeDataBox(0, v); // 二进制类型标志 0
    items.push(M4aWriter.makeBox(name, dataBox));
  }

  private static addCover(items: Uint8Array[], coverData?: ArrayBuffer, coverMime?: string): void {
    if (!coverData || coverData.byteLength === 0) {
      return;
    }
    const indicator: number = (coverMime && coverMime.indexOf('png') >= 0) ? DATA_TYPE_PNG : DATA_TYPE_JPEG;
    const dataBox: Uint8Array = M4aWriter.makeDataBox(indicator, new Uint8Array(coverData));
    items.push(M4aWriter.makeBox('covr', dataBox));
  }

  /** data 盒子：类型标志(4) + locale(4=0) + 值 */
  private static makeDataBox(indicator: number, value: Uint8Array): Uint8Array {
    const body = new Uint8Array(8 + value.length);
    body[0] = (indicator >>> 24) & 0xFF;
    body[1] = (indicator >>> 16) & 0xFF;
    body[2] = (indicator >>> 8) & 0xFF;
    body[3] = indicator & 0xFF;
    // locale 4 字节保持 0
    body.set(value, 8);
    return M4aWriter.makeBox('data', body);
  }

  // ===================== 块偏移修正 =====================

  private static patchChunkOffsets(moov: Uint8Array, delta: number): void {
    M4aWriter.walkPatch(moov, 8, moov.length, delta);
  }

  /** 递归进入容器盒子，定位并修正 stco / co64 */
  private static walkPatch(buf: Uint8Array, start: number, end: number, delta: number): void {
    let off: number = start;
    while (off + 8 <= end) {
      const size: number = M4aWriter.readU32BE(buf, off);
      if (size < 8 || off + size > end) {
        break;
      }
      const type: string = M4aWriter.readAscii(buf, off + 4, 4);
      const contentStart: number = off + 8;
      const contentEnd: number = off + size;
      if (type === 'stco') {
        M4aWriter.patchStco(buf, contentStart, contentEnd, delta);
      } else if (type === 'co64') {
        M4aWriter.patchCo64(buf, contentStart, contentEnd, delta);
      } else if (M4aWriter.isContainer(type)) {
        M4aWriter.walkPatch(buf, contentStart, contentEnd, delta);
      }
      off += size;
    }
  }

  private static isContainer(type: string): boolean {
    return type === 'trak' || type === 'mdia' || type === 'minf' || type === 'stbl';
  }

  /** stco：版本/标志(4) + 条目数(4) + 条目(4,大端) */
  private static patchStco(buf: Uint8Array, contentStart: number, contentEnd: number, delta: number): void {
    if (contentStart + 8 > contentEnd) {
      return;
    }
    const count: number = M4aWriter.readU32BE(buf, contentStart + 4);
    let p: number = contentStart + 8;
    for (let i = 0; i < count && p + 4 <= contentEnd; i++) {
      const v: number = (M4aWriter.readU32BE(buf, p) + delta) >>> 0;
      M4aWriter.writeU32BE(buf, p, v);
      p += 4;
    }
  }

  /** co64：版本/标志(4) + 条目数(4) + 条目(8,大端) */
  private static patchCo64(buf: Uint8Array, contentStart: number, contentEnd: number, delta: number): void {
    if (contentStart + 8 > contentEnd) {
      return;
    }
    const count: number = M4aWriter.readU32BE(buf, contentStart + 4);
    let p: number = contentStart + 8;
    for (let i = 0; i < count && p + 8 <= contentEnd; i++) {
      const hi: number = M4aWriter.readU32BE(buf, p);
      const lo: number = M4aWriter.readU32BE(buf, p + 4);
      const val: number = hi * 0x100000000 + lo + delta;
      M4aWriter.writeU64BE(buf, p, val);
      p += 8;
    }
  }

  // ===================== 盒子工具 =====================

  private static findBox(buf: Uint8Array, start: number, end: number, type: string): BoxRange | null {
    let off: number = start;
    while (off + 8 <= end) {
      const size: number = M4aWriter.readU32BE(buf, off);
      if (size < 8) {
        break;
      }
      const boxEnd: number = Math.min(off + size, end);
      const t: string = M4aWriter.readAscii(buf, off + 4, 4);
      if (t === type) {
        return { start: off, contentStart: off + 8, end: boxEnd };
      }
      off += size;
    }
    return null;
  }

  /** meta 子盒子起点：FullBox 时跳过 4 字节版本/标志，否则不跳 */
  private static metaChildrenStart(meta: Uint8Array): number {
    const withVf: number = 8 + 4;
    if (M4aWriter.looksLikeBox(meta, withVf, meta.length)) {
      return withVf;
    }
    if (M4aWriter.looksLikeBox(meta, 8, meta.length)) {
      return 8;
    }
    return withVf;
  }

  private static looksLikeBox(buf: Uint8Array, off: number, end: number): boolean {
    if (off + 8 > end) {
      return false;
    }
    const size: number = M4aWriter.readU32BE(buf, off);
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

  private static makeBox(type: string, body: Uint8Array): Uint8Array {
    const size: number = 8 + body.length;
    const out = new Uint8Array(size);
    out[0] = (size >>> 24) & 0xFF;
    out[1] = (size >>> 16) & 0xFF;
    out[2] = (size >>> 8) & 0xFF;
    out[3] = size & 0xFF;
    for (let i = 0; i < 4; i++) {
      out[4 + i] = type.charCodeAt(i) & 0xFF;
    }
    out.set(body, 8);
    return out;
  }

  private static concat(parts: Uint8Array[]): Uint8Array {
    let len: number = 0;
    for (const p of parts) {
      len += p.length;
    }
    const out = new Uint8Array(len);
    let o: number = 0;
    for (const p of parts) {
      out.set(p, o);
      o += p.length;
    }
    return out;
  }

  private static toBytes(arr: number[]): Uint8Array {
    const out = new Uint8Array(arr.length);
    for (let i = 0; i < arr.length; i++) {
      out[i] = arr[i] & 0xFF;
    }
    return out;
  }

  private static parseInt(s: string): number {
    const v: number = Number.parseInt(s.trim(), 10);
    return Number.isNaN(v) ? 0 : v;
  }

  private static readU32BE(bytes: Uint8Array, pos: number): number {
    return ((bytes[pos] << 24) | (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | (bytes[pos + 3])) >>> 0;
  }

  private static readU64BE(bytes: Uint8Array, pos: number): number {
    const hi: number = M4aWriter.readU32BE(bytes, pos);
    const lo: number = M4aWriter.readU32BE(bytes, pos + 4);
    return hi * 0x100000000 + lo;
  }

  private static writeU32BE(bytes: Uint8Array, pos: number, n: number): void {
    bytes[pos] = (n >>> 24) & 0xFF;
    bytes[pos + 1] = (n >>> 16) & 0xFF;
    bytes[pos + 2] = (n >>> 8) & 0xFF;
    bytes[pos + 3] = n & 0xFF;
  }

  private static writeU64BE(bytes: Uint8Array, pos: number, n: number): void {
    const hi: number = Math.floor(n / 0x100000000);
    const lo: number = n >>> 0;
    M4aWriter.writeU32BE(bytes, pos, hi);
    M4aWriter.writeU32BE(bytes, pos + 4, lo);
  }

  private static readAscii(bytes: Uint8Array, from: number, len: number): string {
    let s: string = '';
    for (let i = 0; i < len; i++) {
      s += String.fromCharCode(bytes[from + i]);
    }
    return s;
  }

  private static pushU32BE(buf: number[], n: number): void {
    buf.push((n >>> 24) & 0xFF, (n >>> 16) & 0xFF, (n >>> 8) & 0xFF, n & 0xFF);
  }

  private static pushAscii(buf: number[], str: string): void {
    for (let i = 0; i < str.length; i++) {
      buf.push(str.charCodeAt(i) & 0xFF);
    }
  }

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
