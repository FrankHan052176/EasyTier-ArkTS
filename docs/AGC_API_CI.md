# AGC API CI

The `ohos` workflow builds the signed `publish/release` App and uses the AppGallery Connect API Client flow.

Normal `main` and Core dispatch runs upload the App, register its package and submit an
invitation test version. A published GitHub Release uses the same publish signing
configuration, but only uploads and registers the App package in AGC; it waits for package
processing and deliberately does not create, update or submit an AGC test version. The formal
AppGallery version remains a manual release operation. Build artifacts and uploaded package
files include the channel suffix (`-development.app` or `-stable.app`) so the two delivery
paths remain distinguishable even when they use the same App version name.

Configure these repository Secrets:

- `AGC_CLIENT_ID`
- `AGC_CLIENT_SECRET`
- `AGC_APP_ID`

The API Client must be a team-level client (`N/A` project) with permission to upload packages and manage testing versions. The default China endpoint is `connect-api.cloud.huawei.com`; override it with the repository variable `AGC_API_DOMAIN` only when the AGC data-processing region requires another endpoint.

Optional repository variables:

- `AGC_API_DOMAIN`: defaults to `connect-api.cloud.huawei.com`.
- `AGC_TEST_DURATION_DAYS`: invitation-test lifetime in days; defaults to `14`.

The workflow only creates HarmonyOS invitation testing versions: `testType=3` and `onshelfSelfDetect=0`. It obtains a token, requests a short-lived upload URL, and uploads the `.app` once. The resulting `objectId` is registered once with `distributeMode=2` (testing and AppGallery listing) and that same package ID is bound to the invitation test version. It then queries every invitation-test group through the paginated `/api/app-test/v1/test-group/list` API. `appId` is sent as a request header for that API.

The update request refuses to proceed without at least one group. It writes every `groupId`, a start time one hour after the current UTC time, an end time after `AGC_TEST_DURATION_DAYS`, `displayArea="1"`, and `needShareLink=0`. `AGC_NOTIFY_ON_PUSH=1` limits test notifications to the first attempt of an ArkTS `push` run; dispatches, manual runs, and retries do not notify testers. The Pro workflow keeps this setting at `0`.

The test description is deliberately constrained to 30 characters (stricter than the API maximum): `同步上游 <HAR version>` for a Core dispatch, the push commit message for a push, and the current SHA for a manual run. The same text is sent in both the version-creation request and `openTestInfo.testDesc`, which is the test description configurable in AppGallery Connect. GitHub artifacts keep their full provenance name; if that name exceeds the AGC 64-byte package-file limit, the uploaded package uses `<app name>-<Core version>.app` (or a hash fallback) while retaining the same signed App content. The script does not print the Client Secret or access token. When the three required Secrets are absent, the AGC step is skipped and the signed GitHub artifact is still produced.

Before the App-level `publish/release` build, CI derives its package version from the installed Core HAR. For `2.6.4-52`, it writes `versionName=2.6.4.52`. Its `versionCode` is `<Core version without dots><UTC day of year><daily ohos build number>`; the Build Number is calculated from the workflow run sequence for the current UTC day, constrained to `1..99`, zero-padded to two digits, and exported as the `core_har` step's `build_number` output. This mutation is limited to the runner checkout, so the repository's baseline `AppScope/app.json5` is not changed. Local builds using the `default` debug signing configuration do not run this CI mutation: they retain the checked-in `versionName=0.0.1` and `versionCode=99999999`, while the selected build mode remains independent and follows the local Hvigor/DevEco build setting.

Official API references:

- [AppGallery Connect API](https://developer.huawei.com/consumer/cn/doc/app/agc-help-connect-api-0000002236015554)
- [API Client authentication](https://developer.huawei.com/consumer/cn/doc/app/agc-help-connect-api-obtain-server-auth-0000002271134661)
- [Upload Management API](https://developer.huawei.com/consumer/cn/doc/app/agc-help-upload-api-reference-0000002236041486)
- [Testing API](https://developer.huawei.com/consumer/cn/doc/app/agc-help-test-api-reference-0000002271000709)
