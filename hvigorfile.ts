import { appPlugin } from "@hadss/hmrouter-plugin";
import { hvigor, getNode, HvigorNode, HvigorPlugin, Task } from '@ohos/hvigor';
import { AppJson, appTasks, OhosHapContext, OhosAppContext, OhosPluginId, Target } from '@ohos/hvigor-ohos-plugin';
import { parse } from 'yaml';
import crypto from "crypto";
import fs from 'fs';
import path from 'path';
const build_time_file = "./entry/src/main/ets/util/info/BuildTime.ets"
const appInfo = "./AppScope/app.json5"
const en_file = "./entry/src/main/resources/base/element/easytier.json"
const cn_file = "./entry/src/main/resources/zh/element/easytier.json"
const cn = "https://ghfast.top/https://raw.githubusercontent.com/EasyTier/EasyTier/main/easytier-web/frontend-lib/src/locales/cn.yaml"
const en = "https://ghfast.top/https://raw.githubusercontent.com/EasyTier/EasyTier/main/easytier-web/frontend-lib/src/locales/en.yaml"
function calcHash(content: string): string {
    return crypto.createHash("sha256").update(content).digest("hex");
}
function shouldSkipWrite(filePath: string, newContent: string): boolean {
    if (!fs.existsSync(filePath)) return false;
    const oldContent = fs.readFileSync(filePath, "utf8");
    return calcHash(oldContent) === calcHash(newContent);
}
function loadSigningConfigs() {
    const path = './signing/signingConfigs.json';
    try {
        fs.accessSync(path);
    } catch (e) {
        if (e.code !== 'ENOENT') {
            console.error(e);
        }
        return [];
    }
    const data = fs.readFileSync(path);
    return JSON.parse(data.toString());
}
function loadBUILDNUMBER() {
    const path = './BUILDNUMBER.txt';
    try {
        fs.accessSync(path);
    } catch (e) {
        if (e.code !== 'ENOENT') {
            console.error(e);
        }
        return [];
    }
    const num = fs.readFileSync(path).toString().split(".")[1];
    return num.length == 1?"0"+num:num;
}
function loadAppInfo() {
    try {
        fs.accessSync(appInfo);
    } catch (e) {
        if (e.code !== 'ENOENT') {
            console.error(e);
        }
        return [];
    }
    const data = fs.readFileSync(appInfo);
    return JSON.parse(data.toString());
}
function updateBuildTime() {
    const now = new Date();
    const buildTimeString = now.toISOString();
    const info = loadAppInfo();
    const appContext = getNode(__filename).getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    const ohpmInfo = appContext?.getOhpmDependencyInfo?.() ?? {};
    const core = ohpmInfo["easytier-ohrs"];
    const coreVersion = core != undefined ? core.version : "2.4.5-0";
    try {
        fs.writeFileSync(
          build_time_file,
            `export const BUILD_TIME:string = "${buildTimeString}"\nexport const APP_VERSION:string = "${info["app"]["versionName"]}"\nexport const APP_VERSION_CODE:string = "${info["app"]["versionCode"]}"\nexport const CORE_VERSION:string = "${coreVersion}"`
        );
        console.log(`> hvigor Build time updated : ${buildTimeString}`);
    } catch (error) {
        console.error(`> hvigor Failed to update build_time.json: ${error}`);
    }
}
async function convertYamlFromUrlToI18nJson(yamlUrl: string, jsonFilePath: string): Promise<void> {
    try {
        const response = await fetch(yamlUrl);
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        const yamlContent = await response.text();
        const parsedObject = parse(yamlContent);
        const i18nData = convertToI18nFormat(parsedObject);
        const jsonString = JSON.stringify(i18nData, null, 2);
        if (shouldSkipWrite(jsonFilePath, jsonString)) {
            console.log(`⏩ 未变更，跳过写入：${path.basename(jsonFilePath)}`);
            return;
        }
        fs.writeFileSync(jsonFilePath, jsonString, 'utf8');
        console.log(`📊 共转换了 ${i18nData.string.length} 个字符串`);
    } catch (error) {
        console.error('❌ 转换失败:', error);
    }
}
function convertToI18nFormat(flatObject: Record<string, any>): { string: Array<{ name: string; value: string }> } {
    const strings: Array<{ name: string; value: string }> = [];
    function processObject(obj: Record<string, any>, prefix: string = ''): void {
        for (const [key, value] of Object.entries(obj)) {
            const fullKey = prefix ? `${prefix.replace("-","_")}_${key}` : key;
            if (typeof value === 'string') {
                strings.push({ name: fullKey, value: value });
            } else if (typeof value === 'object' && value !== null) {
                processObject(value, fullKey);
            }
        }
    }
    processObject(flatObject);
    return { string: strings };
}
function fixFieldName(field: string): string {
    let snake = field.replace(/([A-Z])/g, '_$1').toLowerCase()
    if (field.startsWith("_")) {
        return snake.substring(1)
    }else {
        return snake
    }
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
                resourceTask.beforeRun(async () => {
                    updateBuildTime()
                    convertYamlFromUrlToI18nJson(en,en_file)
                    convertYamlFromUrlToI18nJson(cn,cn_file)
                });
            }
        });
    })
});
function getDayOfYearUTC(date: Date = new Date()): string {
    const beijing = new Date(date.getTime() + 8 * 60 * 60 * 1000);

    const startOfYear = Date.UTC(beijing.getUTCFullYear(), 0, 1);
    const now = Date.UTC(
        beijing.getUTCFullYear(),
        beijing.getUTCMonth(),
        beijing.getUTCDate()
    );

    const day = Math.floor((now - startOfYear) / 86400000) + 1;
    return String(day).padStart(3, '0');
}


function normalizeVersionName(coreVersion: string, fallbackVersion: string, buildNumber: string): string {
    const [baseVersion, buildSuffix] = (coreVersion || "").split("-")
    const rawVersion = (baseVersion || fallbackVersion || "0.0.0")
        .replace(/[^0-9.]/g, "")
    const segments = rawVersion
        .split(".")
        .filter(segment => segment.length > 0)

    while (segments.length < 3) {
        segments.push("0")
    }

    const normalizedPatch = String(Number.parseInt(buildSuffix ?? buildNumber, 10) || 0)
    return [...segments.slice(0, 3), normalizedPatch].join(".")
}

const rootNode = getNode(__filename);
rootNode.afterNodeEvaluate(node => {
    const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    const buildProfileOpt = appContext.getBuildProfileOpt();
    if (!buildProfileOpt['app']['signingConfigs'] || buildProfileOpt['app']['signingConfigs'].length == 0) {
        console.log("✅ 覆写签名")
        buildProfileOpt['app']['signingConfigs'] = loadSigningConfigs();
    }
    appContext.setBuildProfileOpt(buildProfileOpt);
    const ohpmInfo = appContext.getOhpmDependencyInfo();
    const core = ohpmInfo["easytier-ohrs"]
    const coreVersion = core != undefined?core.version:"2.4.5-0";
    const buildNumber = loadBUILDNUMBER()
    const appJson5: AppJson.AppOptObj = appContext.getAppJsonOpt();
    const version = (""+coreVersion).split("-")[0].replace(".","").replace(".","")
    appJson5.app.versionName = normalizeVersionName(coreVersion, appJson5.app.versionName, buildNumber)
    appJson5.app.versionCode = Number.parseInt(version+getDayOfYearUTC()+buildNumber)
    appContext.setAppJsonOpt(appJson5);
    console.log("versionName: "+appJson5.app.versionName)
    console.log("versionCode: "+appJson5.app.versionCode)
})
export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[appPlugin({ ignoreModuleNames: [] })]         /* Custom plugin to extend the functionality of Hvigor. */
}
