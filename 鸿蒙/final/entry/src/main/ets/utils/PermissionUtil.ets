// entry/src/main/ets/utils/PermissionUtil.ets
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = '[Permission]';
const DOMAIN: number = 0x0000;

export class PermissionUtil {
  static readonly REQUIRED_PERMISSIONS: Array<Permissions> = [
    'ohos.permission.CAMERA',
    'ohos.permission.MICROPHONE',
    'ohos.permission.INTERNET'
  ];

  static async checkPermissions(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();

      for (const permission of PermissionUtil.REQUIRED_PERMISSIONS) {
        const grantStatus: abilityAccessCtrl.GrantStatus = await atManager.checkAccessToken(
          context.applicationInfo.accessTokenId,
          permission
        );

        hilog.info(DOMAIN, TAG, '检查权限 %{public}s: %{public}d', permission, grantStatus);

        if (grantStatus !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          hilog.warn(DOMAIN, TAG, '权限未授予：%{public}s', permission);
          return false;
        }
      }
      return true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, '检查权限失败：%{public}s', JSON.stringify(error));
      return false;
    }
  }

  static async requestPermissions(context: common.UIAbilityContext): Promise<boolean> {
    try {
      hilog.info(DOMAIN, TAG, '开始请求权限');
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();

      const result = await atManager.requestPermissionsFromUser(
        context,
        PermissionUtil.REQUIRED_PERMISSIONS
      );

      hilog.info(DOMAIN, TAG, '权限请求结果：%{public}s', JSON.stringify(result.authResults));

      const allGranted: boolean = result.authResults.every((status: number) =>
      status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
      );

      hilog.info(DOMAIN, TAG, '所有权限已授予：%{public}s', String(allGranted));
      return allGranted;
    } catch (error) {
      hilog.error(DOMAIN, TAG, '请求权限失败：%{public}s', JSON.stringify(error));
      return false;
    }
  }
}