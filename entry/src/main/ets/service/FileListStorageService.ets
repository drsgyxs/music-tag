/**
 * 已导入文件列表存储服务
 *
 * 用 Preferences 持久化主页的音频文件列表，App 重启后仍能恢复。
 * 列表中保存的是 DocumentViewPicker 选中并经 fileShare 持久化授权的 URI，
 * 需配合 FilePermissionService 在访问前激活权限。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AudioFileEntry, AudioFileEntryHelper } from '../model/AudioFileEntry';

const PREF_STORE: string = 'music_tag_store';
const KEY_FILE_LIST: string = 'imported_file_list';

export class FileListStorageService {
  private static instance: FileListStorageService;
  private store: preferences.Preferences | null = null;

  private constructor() {}

  static getInstance(): FileListStorageService {
    if (!FileListStorageService.instance) {
      FileListStorageService.instance = new FileListStorageService();
    }
    return FileListStorageService.instance;
  }

  private getStore(): preferences.Preferences | null {
    if (this.store) {
      return this.store;
    }
    try {
      const context = AppStorage.get<common.UIAbilityContext>('appContext');
      if (!context) {
        console.error('FileListStorageService: 未获取到 appContext');
        return null;
      }
      this.store = preferences.getPreferencesSync(context, { name: PREF_STORE });
      return this.store;
    } catch (e) {
      console.error('打开 Preferences 失败:', e);
      return null;
    }
  }

  /** 读取已导入文件列表（按导入时间倒序） */
  loadList(): AudioFileEntry[] {
    const store = this.getStore();
    if (!store) {
      return [];
    }
    try {
      const json = store.getSync(KEY_FILE_LIST, '') as string;
      const list = AudioFileEntryHelper.parse(json);
      list.sort((a, b) => b.addedTime - a.addedTime);
      return list;
    } catch (e) {
      console.error('读取文件列表失败:', e);
      return [];
    }
  }

  /** 覆盖保存整个列表 */
  saveList(list: AudioFileEntry[]): void {
    const store = this.getStore();
    if (!store) {
      return;
    }
    try {
      store.putSync(KEY_FILE_LIST, AudioFileEntryHelper.stringify(list));
      store.flush();
    } catch (e) {
      console.error('保存文件列表失败:', e);
    }
  }

  /**
   * 追加文件（按 uri 去重，已存在则更新信息并刷新时间），返回更新后的列表。
   */
  addEntries(entries: AudioFileEntry[]): AudioFileEntry[] {
    const list = this.loadList();
    for (const entry of entries) {
      const idx = list.findIndex((e) => e.uri === entry.uri);
      if (idx >= 0) {
        list[idx] = entry;
      } else {
        list.push(entry);
      }
    }
    this.saveList(list);
    list.sort((a, b) => b.addedTime - a.addedTime);
    return list;
  }

  /** 按 uri 删除一项，返回更新后的列表 */
  removeEntry(uri: string): AudioFileEntry[] {
    const list = this.loadList().filter((e) => e.uri !== uri);
    this.saveList(list);
    return list;
  }
}
