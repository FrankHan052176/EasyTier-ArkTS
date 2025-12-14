import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { appPlugin } from "@hadss/hmrouter-plugin";
import { hvigor, getNode, HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { appTasks, OhosHapContext, OhosAppContext, OhosPluginId, Target } from '@ohos/hvigor-ohos-plugin';
import { parse } from 'yaml';
import crypto from "crypto";
import fs from 'fs';
import path from 'path';
import protobuf from "protobufjs";
import { execSync } from "child_process";
const scalarTypeMap = {
    string: "string",
    bool: "boolean",
    bytes: "Uint8Array",
    int32: "number",
    uint32: "number",
    sint32: "number",
    fixed32: "number",
    sfixed32: "number",
    int64: "number",
    uint64: "number",
    sint64: "number",
    fixed64: "number",
    sfixed64: "number",
    double: "number",
    float: "number",
};
const build_time_file = "./entry/src/main/ets/util/info/BuildTime.ets"
const appInfo = "./AppScope/app.json5"
const en_file = "./entry/src/main/resources/base/element/easytier.json"
const cn_file = "./entry/src/main/resources/zh/element/easytier.json"
const cn = "https://ghfast.top/https://raw.githubusercontent.com/EasyTier/EasyTier/main/easytier-web/frontend-lib/src/locales/cn.yaml"
const en = "https://ghfast.top/https://raw.githubusercontent.com/EasyTier/EasyTier/main/easytier-web/frontend-lib/src/locales/en.yaml"
const proto = "https://ghfast.top/https://raw.githubusercontent.com/EasyTier/EasyTier/refs/heads/main/easytier/src/proto/"
function calcHash(content: string): string {
    return crypto.createHash("sha256").update(content).digest("hex");
}
function shouldSkipWrite(filePath: string, newContent: string): boolean {
    if (!fs.existsSync(filePath)) return false;
    const oldContent = fs.readFileSync(filePath, "utf8");
    return calcHash(oldContent) === calcHash(newContent);
}
function loadSigningConfigs() {
    const path = './signingConfigs.json';
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
async function downloadProtoFile(fileName: string): Promise<boolean> {
    try {
        const dir = path.resolve(__dirname, "./proto");
        const filePath = path.join(dir, fileName+".proto");
        const response = await fetch(proto+fileName+".proto");
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        const protoContent = await response.text();
        if (shouldSkipWrite(filePath, protoContent)) {
            console.log(`⏩ 未变更，跳过下载：${fileName}.proto`);
            return false;
        }
        fs.writeFileSync(filePath, protoContent, 'utf8');
        console.log(`✅ 已下载并更新：${fileName}.proto`);
        return true;
    } catch (error) {
        console.error('❌ 转换失败:', error);
        return false;
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
                    const files = [
                        "api_manage",
                        "common",
                        "peer_rpc",
                        "api_instance",
                        "acl",
                        "error",
                    ];
                    let results = await Promise.all(files.map(downloadProtoFile));
                    const changed = results.some(Boolean);
                    if (changed) {
                        console.log("🔄 检测到 proto 文件更新，重新生成...");
                        execSync("buf generate", {
                            cwd: path.resolve(__dirname, "."),
                            stdio: "inherit"
                        });
                        const mapping = {};
                        const idMapping = {};
                        const nameMapping = {};
                        const dir = path.resolve(__dirname, "./proto");
                        const root = await protobuf.load(path.join(dir, "api_manage.proto"))
                        const message = root.lookupType("NetworkConfig")!;
                        for (const [fieldName, field] of Object.entries(message.fields)) {
                            const tsType = scalarTypeMap[field.type] || field.type;
                            const finalType = field.rule === "repeated" ? `${tsType}[]` : tsType;
                            const finalName = fixFieldName(fieldName);
                            const id = ""+field.id;
                            mapping[finalName] = finalType;
                            idMapping[finalName] = id;
                            nameMapping[id] = finalName;
                        }
                        fs.writeFileSync(
                            "./entry/src/main/ets/protobuf/proto-type-map.ts",
                            "export const NetworkConfigTypeMap = " + JSON.stringify(mapping, null, 2)+"\n"+
                              "export const NetworkConfigFieldIdMap = " + JSON.stringify(idMapping, null, 2)+"\n"+
                                "export const NetworkConfigIdFieldMap = " + JSON.stringify(nameMapping, null, 2)
                        );
                        console.log("✅ 生成完成");
                    } else {
                        console.log("⏭️ 所有 proto 文件均无变化，跳过生成");
                    }
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
        console.log("✅ 覆写签名")
        buildProfileOpt['app']['signingConfigs'] = loadSigningConfigs();
    }
    appContext.setBuildProfileOpt(buildProfileOpt);
})
export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[appPlugin({ ignoreModuleNames: [] })]         /* Custom plugin to extend the functionality of Hvigor. */
}
