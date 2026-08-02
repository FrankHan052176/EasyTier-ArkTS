import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { InstanceInfo, PeerInfo } from '../main/ets/class/InstanceInfo';
import {
  InstanceTrafficStats,
  VpnRuntimeStartResultData,
  VPN_MESSAGE_RUNTIME_START_RESULT
} from '../main/ets/infrastructure/bridge/kernel/KernelBridgeTypes';
import { parseVpnBridgeMessage } from '../main/ets/infrastructure/bridge/kernel/SocketCodec';
import { redactSensitiveLogText } from '../main/ets/shared/logging/LogRedaction';
import { NatTypeValue, natTypeToText } from '../main/ets/types/runtime/RuntimeTypes';
import {
  THIRD_PARTY_API_SCHEMA_VERSION,
  THIRD_PARTY_OPERATION_START_INSTANCE,
  THIRD_PARTY_REQUEST_TTL_MS,
  THIRD_PARTY_RESULT_REQUEST_EXPIRED,
  THIRD_PARTY_SNAPSHOT_TTL_MS,
  ThirdPartyApiRequestPayload,
  ThirdPartyApiSnapshotPayload,
  ThirdPartyApiValidator
} from '../main/ets/services/integration/ThirdPartyApiContract';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
    it('redactsSensitiveConfigValues', 0, () => {
      const json = '{"network_secret":"top-secret","password":"pw","instance_id":"safe"}'
      const toml = 'network_secret = "top-secret"'
      const redacted = redactSensitiveLogText(`${json} ${toml}`)
      expect(redacted).assertNotContain('top-secret')
      expect(redacted).assertContain('[REDACTED]')
      expect(redacted).assertContain('instance_id')
    });
    it('calculatesTrafficAsBytesPerSecond', 0, () => {
      const info = new InstanceInfo()
      const baseline: InstanceTrafficStats = {
        configId: 'config',
        instanceId: 'instance',
        rxBytes: 0,
        txBytes: 0,
        peers: []
      }
      const next: InstanceTrafficStats = {
        configId: 'config',
        instanceId: 'instance',
        rxBytes: 2048,
        txBytes: 1024,
        peers: []
      }
      info.updateTraffic(baseline, 1000)
      info.updateTraffic(next, 3000)
      expect(info.getDownloadRate()).assertEqual(1)
      expect(info.getDownloadRateUnit()).assertEqual('KB/s')
      expect(info.getUploadRate()).assertEqual(512)
      expect(info.getUploadRateUnit()).assertEqual('B/s')
    });
    it('averagesPeerTrafficRatesAndResetsRolledBackCounters', 0, () => {
      const peer = new PeerInfo(1, 'peer', 1, '10.0.0.2')
      peer.push(0, 1000)
      peer.push(1024, 2000)
      peer.push(3072, 4000)
      expect(peer.getRate()).assertEqual(1)
      expect(peer.getRateUnit()).assertEqual('KB/s')
      peer.push(0, 5000)
      expect(peer.getRate()).assertEqual(0)
    });
    it('rendersNatTypesAsText', 0, () => {
      expect(natTypeToText(NatTypeValue.OpenInternet)).assertEqual('公网')
      expect(natTypeToText(NatTypeValue.PortRestricted)).assertEqual('端口受限型')
      expect(natTypeToText(NatTypeValue.Unknown)).assertEqual('未知')
    });
    it('parsesVpnRuntimeStartResult', 0, () => {
      const message = parseVpnBridgeMessage(
        '{"type":"runtime_start_result","data":{"instanceId":"instance","started":true}}')
      expect(message.type).assertEqual(VPN_MESSAGE_RUNTIME_START_RESULT)
      const result = message.data as VpnRuntimeStartResultData
      expect(result.instanceId).assertEqual('instance')
      expect(result.started).assertEqual(true)
    });
    it('validatesThirdPartyApiStartRequest', 0, () => {
      const requestId = '12345678-1234-4234-9234-123456789abc'
      const now = Date.now()
      const payload: ThirdPartyApiRequestPayload = {
        schemaVersion: THIRD_PARTY_API_SCHEMA_VERSION,
        requestId,
        operation: THIRD_PARTY_OPERATION_START_INSTANCE,
        issuedAt: now,
        instanceId: 'office-network'
      }
      const result = ThirdPartyApiValidator.validateRequest(payload, requestId, now)
      expect(result.ok).assertTrue()
    });
    it('requiresInstanceForThirdPartyStartRequest', 0, () => {
      const requestId = '12345678-1234-4234-9234-123456789abc'
      const now = Date.now()
      const payload: ThirdPartyApiRequestPayload = {
        schemaVersion: THIRD_PARTY_API_SCHEMA_VERSION,
        requestId,
        operation: THIRD_PARTY_OPERATION_START_INSTANCE,
        issuedAt: now
      }
      const result = ThirdPartyApiValidator.validateRequest(payload, requestId, now)
      expect(result.ok).assertFalse()
    });
    it('rejectsExpiredThirdPartyApiRequest', 0, () => {
      const requestId = '12345678-1234-4234-9234-123456789abc'
      const now = Date.now()
      const payload: ThirdPartyApiRequestPayload = {
        schemaVersion: THIRD_PARTY_API_SCHEMA_VERSION,
        requestId,
        operation: THIRD_PARTY_OPERATION_START_INSTANCE,
        issuedAt: now - THIRD_PARTY_REQUEST_TTL_MS - 1,
        instanceId: 'office-network'
      }
      const result = ThirdPartyApiValidator.validateRequest(payload, requestId, now)
      expect(result.ok).assertFalse()
      expect(result.code).assertEqual(THIRD_PARTY_RESULT_REQUEST_EXPIRED)
    });
    it('sanitizesThirdPartyInstanceNames', 0, () => {
      const name = ThirdPartyApiValidator.safeInstanceName('  office\u0000network  ')
      expect(name).assertEqual('officenetwork')
    });
    it('rejectsLegacyEnsureOperation', 0, () => {
      expect(ThirdPartyApiValidator.isOperation('ensure_instance_running')).assertFalse()
    });
    it('acceptsFreshThirdPartySnapshot', 0, () => {
      const now = Date.now()
      const snapshot: ThirdPartyApiSnapshotPayload = {
        schemaVersion: THIRD_PARTY_API_SCHEMA_VERSION,
        updatedAt: now,
        ttlMs: THIRD_PARTY_SNAPSHOT_TTL_MS,
        instances: [],
        truncated: false
      }
      expect(ThirdPartyApiValidator.isSnapshotFresh(snapshot, now)).assertTrue()
      expect(ThirdPartyApiValidator.isSnapshotFresh(snapshot, now + THIRD_PARTY_SNAPSHOT_TTL_MS + 1)).assertFalse()
    });
  });
}
