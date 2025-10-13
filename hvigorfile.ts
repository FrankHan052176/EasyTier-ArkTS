import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { hvigor, getNode, HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { appTasks, OhosHapContext, OhosAppContext, OhosPluginId, Target } from '@ohos/hvigor-ohos-plugin';
import fs from 'fs';
import path from 'path';
const targetDir = "src/main/resources/base/element"
const fileName = "build_time.json"
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
function updateBuildTime(dir: string) {
    const filePath = path.join(dir, targetDir, fileName);
    const now = new Date();
    const buildTimeString = now.toISOString();

    try {
        // 确保目录存在
        const dir = path.dirname(filePath);
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
        }

        // 写入构建时间文件
        fs.writeFileSync(filePath, `{
  "string": [
    {
      "name": "build_time",
      "value": "${buildTimeString}"
    }
  ]
}`);
        console.log(`> hvigor Build time updated : ${buildTimeString}`);
    } catch (error) {
        console.error(`> hvigor Failed to update build_time.json: ${error}`);
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
                resourceTask.beforeRun(() => {
                    updateBuildTime(node.getNodeDir().getPath())
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
