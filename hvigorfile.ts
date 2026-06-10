import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { getNode } from '@ohos/hvigor';
import * as signingConfig from './signing-config.json'

const rootNode = getNode(__filename);

rootNode.afterNodeEvaluate(node => {
  try {
    const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    const buildProfileOpt = appContext.getBuildProfileOpt();

    // 应用签名配置
    buildProfileOpt['app']['signingConfigs'] = [
      {
        "name": "default",
        "type": "HarmonyOS",
        "material": {
          "certpath": signingConfig.certpath,
          "storePassword": signingConfig.storePassword,
          "keyAlias": signingConfig.keyAlias,
          "keyPassword": signingConfig.keyPassword,
          "profile": signingConfig.profile,
          "signAlg": signingConfig.signAlg || "SHA256withECDSA",
          "storeFile": signingConfig.storeFile
        }
      }
    ];

    appContext.setBuildProfileOpt(buildProfileOpt);
    console.log('Signing config loaded from signing-config.json');
  } catch (error) {
    console.error('Failed to load signing config:', error);
  }
});

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}