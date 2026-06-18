import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    // 将 context 存入 AppStorage，供各 Service 使用
    AppStorage.setOrCreate<Object>('appContext', this.context);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');


    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      // 沉浸式布局：让内容延伸到状态栏与底部「小白条」之下，
      // 并将系统状态栏 / 导航条背景设为透明，避免底部出现白色矩形。
      // try {
      //   const windowClass = windowStage.getMainWindowSync();
      //   windowClass.setWindowLayoutFullScreen(true)
      //     .catch((err: BusinessError) => {
      //       hilog.error(DOMAIN, 'testTag', 'Failed to set the window layout. Cause: %{public}s', JSON.stringify(err));
      //     });
      //   windowClass.setWindowSystemBarProperties({
      //     statusBarColor: '#00000000',
      //     statusBarContentColor: '#000000',
      //     navigationBarColor: '#00000000',
      //     navigationBarContentColor: '#000000'
      //   }).catch((err: BusinessError) => {
      //     hilog.error(DOMAIN, 'testTag', 'Failed to set the window system bar properties. Cause: %{public}s',
      //       JSON.stringify(err));
      //   });
      //   let type = window.AvoidAreaType.TYPE_SYSTEM; // 以状态栏避让为例
      //   let avoidArea = windowClass.getWindowAvoidArea(type);
      //   let topRectHeight = avoidArea.topRect.height; // 获取状态栏区域高度
      //   AppStorage.setOrCreate('topRectHeight', topRectHeight);
      //
      //   windowClass.on('avoidAreaChange', (data) => {
      //     if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
      //       let topRectHeight = data.area.topRect.height;
      //       AppStorage.setOrCreate('topRectHeight', topRectHeight);
      //     }
      //     // else if (data.type == window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      //     //   let bottomRectHeight = data.area.bottomRect.height;
      //     //   AppStorage.setOrCreate('bottomRectHeight', bottomRectHeight);
      //     // }
      //   });
      //
      // } catch (err) {
      //   hilog.error(DOMAIN, 'testTag', 'Failed to set immersive window. Cause: %{public}s', JSON.stringify(err));
      // }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the home page.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
