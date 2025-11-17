import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import { modulePlugin } from '@hadss/hmrouter-plugin';

export default {
    system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
    plugins: [modulePlugin()]       /* Custom plugin to extend the functionality of Hvigor. */
}