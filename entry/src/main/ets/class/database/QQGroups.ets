import { cloudDatabase } from '@kit.CloudFoundationKit';

class QQGroup extends cloudDatabase.DatabaseObject {
  public qqgroup: string | undefined;

  public naturalbase_ClassName(): string {
    return "qqgroup";
  }
}

class PushToken extends cloudDatabase.DatabaseObject {
  public pushtoken: string | undefined;

  public naturalbase_ClassName(): string {
    return "pushtoken";
  }
}

export { QQGroup, PushToken };