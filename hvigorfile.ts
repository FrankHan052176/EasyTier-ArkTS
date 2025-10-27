import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor, getNode, HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { appTasks, OhosHapContext, OhosAppContext, OhosPluginId, Target } from '@ohos/hvigor-ohos-plugin';
import { parse } from 'yaml';
import fs from 'fs';
import path from 'path';
const build_time_file = "./entry/src/main/ets/util/info/BuildTime.ets"
const appInfo = "./AppScope/app.json5"
const en_file = "./entry/src/main/resources/base/element/easytier.json"
const cn_file = "./entry/src/main/resources/zh/element/easytier.json"
const cn = "https://ghfast.top/https://raw.githubusercontent.com/EasyTier/EasyTier/main/easytier-web/frontend-lib/src/locales/cn.yaml"
const en = "https://ghfast.top/https://raw.githubusercontent.com/EasyTier/EasyTier/main/easytier-web/frontend-lib/src/locales/en.yaml"
function loadSigningConfigs() {
    const path = 'signingConfigs.json';
    try {
        fs.accessSync(path);
    } catch (e) {
        if (e.code !== 'ENOENT') {
            log.error(e);
        }
        return [];
    }
    const data = fs.readFileSync(path);
    return JSON.parse(data);
}
function loadAppInfo() {
    try {
        fs.accessSync(appInfo);
    } catch (e) {
        if (e.code !== 'ENOENT') {
            log.error(e);
        }
        return [];
    }
    const data = fs.readFileSync(appInfo);
    return JSON.parse(data);
}
function updateBuildTime() {
    const now = new Date();
    const buildTimeString = now.toISOString();
    const info = loadAppInfo();
    try {
        fs.writeFileSync(
          build_time_file,
            `export const BUILD_TIME:string = "${buildTimeString}"\nexport const APP_VERSION:string = "${info["app"]["versionName"]}"\nexport const APP_VERSION_CODE:string = "${info["app"]["versionCode"]}"`
        );
        console.log(`> hvigor Build time updated : ${buildTimeString}`);
    } catch (error) {
        console.error(`> hvigor Failed to update build_time.json: ${error}`);
    }
}
async function convertYamlFromUrlToI18nJson(yamlUrl: string, jsonFilePath: string): Promise<void> {
    try {
        const response = await fetch(yamlUrl);
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        const yamlContent = await response.text();
        console.log('✅ YAML 内容获取成功');
        const parsedObject = parse(yamlContent);
        const i18nData = convertToI18nFormat(parsedObject);
        fs.writeFileSync(jsonFilePath, JSON.stringify(i18nData, null, 2), 'utf8');
        console.log(`📊 共转换了 ${i18nData.string.length} 个字符串`);
    } catch (error) {
        console.error('❌ 转换失败:', error);
    }
}
function convertToI18nFormat(flatObject: Record<string, any>): { string: Array<{ name: string; value: string }> } {
    const strings: Array<{ name: string; value: string }> = [];
    function processObject(obj: Record<string, any>, prefix: string = ''): void {
        for (const [key, value] of Object.entries(obj)) {
            const fullKey = prefix ? `${prefix}_${key}` : key;

            if (typeof value === 'string') {
                strings.push({
                    name: fullKey,
                    value: value
                });
            } else if (typeof value === 'object' && value !== null) {
                processObject(value, fullKey);
            }
        }
    }
    processObject(flatObject);
    return { string: strings };
}
hvigor.nodesEvaluated(() => {
    const rootNode = hvigor.getRootNode();
    rootNode.subNodes((node: HvigorNode) => {
        const hapContext = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext;
        if (!hapContext) {
            return;
        }
        hapContext.targets((target: Target) => {
            const targetName = target.getTargetName();
            const resourceTask: Task | undefined = node.getTaskByName(`${targetName}@ProcessStartupConfig`);
            if (resourceTask) {
                resourceTask.beforeRun(() => {
                    updateBuildTime()
                    convertYamlFromUrlToI18nJson(en,en_file)
                    convertYamlFromUrlToI18nJson(cn,cn_file)
                });
            }
        });
    })
});
const rootNode = getNode(__filename);
rootNode.afterNodeEvaluate(node => {
    const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    const buildProfileOpt = appContext.getBuildProfileOpt();
    if (!buildProfileOpt['app']['signingConfigs'] || buildProfileOpt['app']['signingConfigs'].length == 0) {
        buildProfileOpt['app']['signingConfigs'] = loadSigningConfigs();
    }
    appContext.setBuildProfileOpt(buildProfileOpt);
})
export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[]         /* Custom plugin to extend the functionality of Hvigor. */
}
