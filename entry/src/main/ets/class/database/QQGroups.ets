import { cloudDatabase } from '@kit.CloudFoundationKit';

class QQGroup extends cloudDatabase.DatabaseObject{
  public naturalbase_ClassName(): string {
    return "qqgroup";
  }
  public qqgroup: string | undefined;
}

class PushToken extends cloudDatabase.DatabaseObject{
  public naturalbase_ClassName(): string {
    return "pushtoken";
  }
  public pushtoken: string | undefined;
}

export { QQGroup, PushToken };