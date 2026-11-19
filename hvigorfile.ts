import { appPlugin } from "@hadss/hmrouter-plugin";
import { hvigor, getNode, HvigorNode, Task } from '@ohos/hvigor';
import { AppJson, appTasks, OhosHapContext, OhosAppContext, OhosPluginId, Target } from '@ohos/hvigor-ohos-plugin';
import { parse } from 'yaml';
import { execFileSync } from 'child_process';
import crypto from "crypto";
import fs from 'fs';
import path from 'path';
const build_time_file = "./entry/src/main/ets/util/info/BuildTime.ets"
const agcd_changelog_ets_file = "./entry/src/main/ets/util/info/AgcdChangelog.ets"
const agcd_changelog_json_file = "./agcd-changelog.json"
const local_core_har_file = "./easytier-ohrs-0.0.1.har"
const oh_modules_core_dir = "./oh_modules/easytier-ohrs"
const oh_modules_core_stamp_file = "./oh_modules/.easytier-ohrs-har.sha256"
const appInfo = "./AppScope/app.json5"
const en_file = "./entry/src/main/resources/base/element/easytier.json"
const cn_file = "./entry/src/main/resources/zh/element/easytier.json"
const cn = "https://ghfast.top/https://raw.githubusercontent.com/EasyTier/EasyTier/main/easytier-web/frontend-lib/src/locales/cn.yaml"
const en = "https://ghfast.top/https://raw.githubusercontent.com/EasyTier/EasyTier/main/easytier-web/frontend-lib/src/locales/en.yaml"
const signingConfigFileName = "signingConfigs.json"

interface AgcdSourceSection {
    triggerId?: string;
    sourceName: string;
    repo: string;
    version: string;
    summary: string;
    items: string[];
}

interface AgcdChangelogPayload {
    projectId?: string;
    versionName: string;
    versionCode: number;
    releaseDate: string;
    channel?: string;
    summary: string;
    mainProject?: AgcdSourceSection;
    upstreams: AgcdSourceSection[];
    generatedAt: number;
}

function calcHash(content: string | Buffer): string {
    return crypto.createHash("sha256").update(content).digest("hex");
}
function shouldSkipWrite(filePath: string, newContent: string): boolean {
    if (!fs.existsSync(filePath)) return false;
    const oldContent = fs.readFileSync(filePath, "utf8");
    return calcHash(oldContent) === calcHash(newContent);
}
function writeFileIfChanged(filePath: string, content: string): void {
    if (shouldSkipWrite(filePath, content)) {
        return;
    }
    fs.writeFileSync(filePath, content, "utf8");
}
function syncInjectedCoreHar(): void {
    if (!fs.existsSync(local_core_har_file) || !fs.existsSync(oh_modules_core_dir)) {
        return;
    }
    try {
        const harBytes = fs.readFileSync(local_core_har_file);
        const harSha256 = calcHash(harBytes);
        const targetPkgJson = path.join(oh_modules_core_dir, "oh-package.json5");
        if (fs.existsSync(oh_modules_core_stamp_file) && fs.existsSync(targetPkgJson)) {
            const recorded = fs.readFileSync(oh_modules_core_stamp_file, "utf8").trim();
            if (recorded === harSha256) {
                return;
            }
        }
        const realTargetDir = fs.realpathSync(oh_modules_core_dir);
        const tempExtractDir = path.resolve("./oh_modules/.easytier-ohrs-sync-tmp");
        fs.rmSync(tempExtractDir, { recursive: true, force: true });
        fs.mkdirSync(tempExtractDir, { recursive: true });
        try {
            execFileSync("tar", ["-xzf", path.resolve(local_core_har_file), "--strip-components=1", "-C", tempExtractDir]);
            for (const entry of fs.readdirSync(realTargetDir)) {
                fs.rmSync(path.join(realTargetDir, entry), { recursive: true, force: true });
            }
            for (const entry of fs.readdirSync(tempExtractDir)) {
                fs.cpSync(path.join(tempExtractDir, entry), path.join(realTargetDir, entry), { recursive: true });
            }
            fs.writeFileSync(oh_modules_core_stamp_file, `${harSha256}\n`, "utf8");
            console.log(`> hvigor Synced injected ${local_core_har_file} into oh_modules (${harSha256.slice(0, 12)})`);
        } finally {
            fs.rmSync(tempExtractDir, { recursive: true, force: true });
        }
    } catch (error) {
        console.warn(`> hvigor Warning: failed to sync ${local_core_har_file} into oh_modules: ${error}`);
    }
}
function normalizeStringList(raw: unknown): string[] {
    if (!Array.isArray(raw)) {
        return [];
    }
    return raw
        .filter((item): item is string => typeof item === "string")
        .map(item => item.trim())
        .filter(item => item.length > 0);
}
function normalizeAgcdSection(raw: unknown, fallbackSourceName: string): AgcdSourceSection | undefined {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
        return undefined;
    }
    const record = raw as Record<string, unknown>;
    const sourceName = typeof record.sourceName === "string" && record.sourceName.trim().length > 0
        ? record.sourceName.trim()
        : fallbackSourceName;
    const repo = typeof record.repo === "string" ? record.repo.trim() : "";
    const version = typeof record.version === "string" ? record.version.trim() : "";
    const summary = typeof record.summary === "string" ? record.summary.trim() : "";
    const triggerId = typeof record.triggerId === "string" && record.triggerId.trim().length > 0
        ? record.triggerId.trim()
        : undefined;
    const items = normalizeStringList(record.items);
    const section: AgcdSourceSection = {
        sourceName,
        repo,
        version,
        summary,
        items
    };
    if (triggerId) {
        section.triggerId = triggerId;
    }
    return section;
}
function loadAgcdChangelog(): AgcdChangelogPayload | undefined {
    if (!fs.existsSync(agcd_changelog_json_file)) {
        return undefined;
    }
    try {
        const rawText = fs.readFileSync(agcd_changelog_json_file, "utf8");
        const parsed = JSON.parse(rawText) as Record<string, unknown>;
        const versionName = typeof parsed.versionName === "string" ? parsed.versionName.trim() : "";
        const rawCode = typeof parsed.versionCode === "number"
            ? parsed.versionCode
            : Number.parseInt(String(parsed.versionCode ?? "0"), 10);
        const versionCode = Number.isSafeInteger(rawCode) && rawCode > 0 ? rawCode : 0;
        const releaseDate = typeof parsed.releaseDate === "string" ? parsed.releaseDate.trim() : "";
        const channel = parsed.channel === "stable" ? "stable" : (parsed.channel === "development" ? "development" : undefined);
        const summary = typeof parsed.summary === "string" ? parsed.summary.trim() : "";
        const generatedAt = typeof parsed.generatedAt === "number" && Number.isFinite(parsed.generatedAt)
            ? parsed.generatedAt
            : 0;
        const mainProject = normalizeAgcdSection(parsed.mainProject, "主项目");
        const upstreams: AgcdSourceSection[] = [];
        if (Array.isArray(parsed.upstreams)) {
            parsed.upstreams.forEach((item, index) => {
                const normalized = normalizeAgcdSection(item, `上游依赖 ${index + 1}`);
                if (normalized) {
                    upstreams.push(normalized);
                }
            });
        }
        return {
            projectId: typeof parsed.projectId === "string" ? parsed.projectId : undefined,
            versionName,
            versionCode,
            releaseDate,
            channel,
            summary,
            mainProject,
            upstreams,
            generatedAt
        };
    } catch (error) {
        console.warn(`> hvigor Failed to parse ${agcd_changelog_json_file}: ${error}`);
        return undefined;
    }
}
function syncAgcdChangelogEts(agcd: AgcdChangelogPayload | undefined): void {
    const serialized = agcd ? JSON.stringify(agcd) : "";
    const content = `export const AGCD_CHANGELOG_JSON: string = ${JSON.stringify(serialized)}\n`;
    try {
        writeFileIfChanged(agcd_changelog_ets_file, content);
    } catch (error) {
        console.error(`> hvigor Failed to update ${agcd_changelog_ets_file}: ${error}`);
    }
}
function resolveInstalledCoreVersion(appContext?: OhosAppContext): string {
    const pkgJsonPath = path.join(oh_modules_core_dir, "oh-package.json5");
    if (fs.existsSync(pkgJsonPath)) {
        try {
            const text = fs.readFileSync(pkgJsonPath, "utf8");
            const match = text.match(/"version"\s*:\s*"([^"]+)"/);
            if (match && match[1]) {
                return match[1];
            }
        } catch (_) {
        }
    }
    const ohpmInfo = appContext?.getOhpmDependencyInfo?.() ?? {};
    const corePackageName = process.env.CORE_HAR_PACKAGE ?? "easytier-ohrs";
    const core = ohpmInfo[corePackageName];
    return core !== undefined ? core.version : "2.4.5-0";
}
function loadSigningConfigs() {
    const signingDir = process.env.EASYTIER_SIGNING_DIR;
    if (!signingDir) {
        return [];
    }
    const signingConfigPath = path.join(signingDir, signingConfigFileName);
    try {
        fs.accessSync(signingConfigPath, fs.constants.R_OK);
    } catch (error) {
        throw new Error(`Unable to read EasyTier signing configuration from EASYTIER_SIGNING_DIR: ${error}`);
    }
    const configs = JSON.parse(fs.readFileSync(signingConfigPath, 'utf8'));
    if (!Array.isArray(configs)) {
        throw new Error("EasyTier signing configuration must be a JSON array.");
    }
    const hasDefault = configs.some(config => config.name === "default");
    const hasPublish = configs.some(config => config.name === "publish");
    if (!hasDefault || !hasPublish) {
        throw new Error("EasyTier signing configuration must contain default and publish entries.");
    }
    return configs;
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
function resolveReleaseChannel(agcd?: AgcdChangelogPayload): string {
    if (process.env.EASYTIER_RELEASE_CHANNEL === "stable") {
        return "stable";
    }
    if (process.env.EASYTIER_RELEASE_CHANNEL === "development") {
        return "development";
    }
    return agcd?.channel === "stable" ? "stable" : "development";
}
function resolveReleaseDate(agcd?: AgcdChangelogPayload): string {
    if (process.env.EASYTIER_RELEASE_DATE && process.env.EASYTIER_RELEASE_DATE.length > 0) {
        return process.env.EASYTIER_RELEASE_DATE;
    }
    return agcd?.releaseDate ?? "";
}
function updateBuildTime(agcd?: AgcdChangelogPayload) {
    const now = new Date();
    const buildTimeString = now.toISOString();
    const info = loadAppInfo();
    const appContext = getNode(__filename).getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    const coreVersion = resolveInstalledCoreVersion(appContext);
    const rawAppVersion = info?.["app"]?.["versionName"] ?? "0.0.1";
    const rawAppVersionCode = info?.["app"]?.["versionCode"] ?? 99999999;
    const effectiveVersionName = agcd && agcd.versionName.length > 0 ? agcd.versionName : String(rawAppVersion);
    const effectiveVersionCode = agcd && agcd.versionCode > 0 ? String(agcd.versionCode) : String(rawAppVersionCode);
    try {
        fs.writeFileSync(
          build_time_file,
            `export const BUILD_TIME:string = "${buildTimeString}"\nexport const APP_VERSION:string = "${effectiveVersionName}"\nexport const APP_VERSION_CODE:string = "${effectiveVersionCode}"\nexport const CORE_VERSION:string = "${coreVersion}"\nexport const APP_CHANNEL:string = "${resolveReleaseChannel(agcd)}"\nexport const APP_RELEASE_DATE:string = "${resolveReleaseDate(agcd)}"`
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
                    const agcd = loadAgcdChangelog();
                    syncAgcdChangelogEts(agcd);
                    updateBuildTime(agcd);
                    if (process.env.EASYTIER_SYNC_I18N === "1") {
                        await convertYamlFromUrlToI18nJson(en, en_file);
                        await convertYamlFromUrlToI18nJson(cn, cn_file);
                    }
                });
            }
        });
    })
});
syncInjectedCoreHar();
const rootNode = getNode(__filename);
rootNode.afterNodeEvaluate(node => {
    const appContext = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    const agcd = loadAgcdChangelog();
    syncAgcdChangelogEts(agcd);
    const buildProfileOpt = appContext.getBuildProfileOpt();
    const signingConfigs = loadSigningConfigs();
    if (signingConfigs.length > 0) {
        console.log("> hvigor Injecting EasyTier signing configuration from EASYTIER_SIGNING_DIR.")
        buildProfileOpt['app']['signingConfigs'] = signingConfigs;
        const products = buildProfileOpt['app']['products'];
        if (Array.isArray(products)) {
            products.forEach(product => {
                const productName = product['name'];
                if (productName === "default" || productName === "publish") {
                    product['signingConfig'] = productName;
                }
            });
        }
    }
    appContext.setBuildProfileOpt(buildProfileOpt);
    const appJson5: AppJson.AppOptObj = appContext.getAppJsonOpt();
    if (agcd) {
        if (agcd.versionName.length > 0) {
            appJson5.app.versionName = agcd.versionName;
        }
        if (agcd.versionCode > 0) {
            appJson5.app.versionCode = agcd.versionCode;
        }
    }
    appContext.setAppJsonOpt(appJson5);
    console.log("versionName: "+appJson5.app.versionName)
    console.log("versionCode: "+appJson5.app.versionCode)
})
export default {
    system: appTasks,  /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins:[appPlugin({ ignoreModuleNames: [] })]         /* Custom plugin to extend the functionality of Hvigor. */
}
