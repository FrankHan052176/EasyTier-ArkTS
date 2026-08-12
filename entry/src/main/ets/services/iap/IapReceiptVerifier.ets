import { util } from '@kit.ArkTS'
import { cert } from '@kit.DeviceCertificateKit'
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import BuildProfile from 'BuildProfile'

const EXPECTED_APPLICATION_ID = '6917581172490635834'
const EXPECTED_PRODUCT_ID = 'remote_control'
const EXPECTED_PRODUCT_TYPE = '1'
const LEAF_CERT_OID = '1.3.6.1.4.1.2011.2.415.1.1'
const LEAF_CERT_OID_DER_VALUE: number[] = [
  0x2b, 0x06, 0x01, 0x04, 0x01, 0x8f, 0x5b, 0x02, 0x83, 0x1f, 0x01, 0x01
]

/**
 * Huawei CBG Root CA G2. Source:
 * https://pki.consumer.huawei.com/ca/cer/RootCaG2Ecdsa.cer
 * SHA-256: DF:21:A3:C0:9F:79:54:57:93:05:F8:5C:64:F8:0C:AD:86:F7:98:53:EE:3A:88:7C:1D:EC:95:D2:18:DF:3A:37
 */
const HUAWEI_CBG_ROOT_CA_G2_DER =
  'MIICGjCCAaGgAwIBAgIIShhpn519jNAwCgYIKoZIzj0EAwMwUzELMAkGA1UEBhMCQ04xDzANBgNVBAoMBkh1YXdlaTETMBEGA1UECwwKSHVhd2VpIENCRzEeMBwGA1UEAwwVSHVhd2VpIENCRyBSb290IENBIEcyMB4XDTIwMDMxNjAzMDQzOVoXDTQ5MDMxNjAzMDQzOVowUzELMAkGA1UEBhMCQ04xDzANBgNVBAoMBkh1YXdlaTETMBEGA1UECwwKSHVhd2VpIENCRzEeMBwGA1UEAwwVSHVhd2VpIENCRyBSb290IENBIEcyMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEWidkGnDSOw3/HE2y2GHl+fpWBIa5S+IlnNrsGUvwC1I2QWvtqCHWmwFlFK95zKXiM8s9yV3VVXh7ivN8ZJO3SC5N1TCrvB2lpHMBwcz4DA0kgHCMm/wDec6kOHx1xvCRo0IwQDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUo45a9Vq8cYwqaiVyfkiS4pLcIAAwCgYIKoZIzj0EAwMDZwAwZAIwMypeB7P0IbY7c6gpWcClhRznOJFj8uavrNu2PIoz9KIqr3jnBlBHJs0myI7ntYpEAjBbm8eDMZY5zq5iMZUC6H7UzYSix4Uy1YlsLVV738PtKP9hFTjgDHctXJlC5L7+ZDY='

interface PurchaseData {
  type?: number
  jwsPurchaseOrder?: string
}

interface JwsHeader {
  alg?: string
  typ?: string
  x5c?: string[]
}

export interface PurchaseOrderPayload {
  environment?: string
  purchaseOrderId?: string
  purchaseToken?: string
  applicationId?: string
  productId?: string
  productType?: string
  purchaseOrderRevocationReasonCode?: string
  signedTime?: number
}

export interface VerifiedPurchase {
  payload: PurchaseOrderPayload
  jwsPurchaseOrder: string
}

let trustedRootCertificate: cert.X509Cert | undefined = undefined

function decodeBase64(value: string, urlSafe: boolean = false): Uint8Array {
  let normalized = value.replace(/\s/g, '')
  if (urlSafe) {
    normalized = normalized.replace(/-/g, '+').replace(/_/g, '/')
  }
  while (normalized.length % 4 !== 0) {
    normalized += '='
  }
  return new util.Base64Helper().decodeSync(normalized, util.Type.BASIC)
}

function decodeText(bytes: Uint8Array): string {
  const decoder = util.TextDecoder.create('utf-8', { fatal: true, ignoreBOM: true })
  return decoder.decodeToString(bytes, { stream: false })
}

function encodeText(value: string): Uint8Array {
  return util.TextEncoder.create('utf-8').encodeInto(value)
}

function bytesEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) {
    return false
  }
  for (let index = 0; index < left.length; index++) {
    if (left[index] !== right[index]) {
      return false
    }
  }
  return true
}

function containsBytes(source: Uint8Array, needle: number[]): boolean {
  if (needle.length === 0 || source.length < needle.length) {
    return false
  }
  for (let offset = 0; offset <= source.length - needle.length; offset++) {
    let matches = true
    for (let index = 0; index < needle.length; index++) {
      if (source[offset + index] !== needle[index]) {
        matches = false
        break
      }
    }
    if (matches) {
      return true
    }
  }
  return false
}

function hasRequiredLeafOid(leaf: cert.X509Cert): boolean {
  const oidList = leaf.getExtensionsObject().getOidList(cert.ExtensionOidType.EXTENSION_OID_TYPE_UNCRITICAL)
  for (const oid of oidList.data) {
    if (containsBytes(oid, LEAF_CERT_OID_DER_VALUE)) {
      return true
    }
    try {
      if (decodeText(oid) === LEAF_CERT_OID) {
        return true
      }
    } catch (_) {
    }
  }
  return false
}

async function getTrustedRootCertificate(): Promise<cert.X509Cert> {
  if (trustedRootCertificate !== undefined) {
    return trustedRootCertificate
  }
  trustedRootCertificate = await cert.createX509Cert({
    data: decodeBase64(HUAWEI_CBG_ROOT_CA_G2_DER),
    encodingFormat: cert.EncodingFormat.FORMAT_DER
  })
  return trustedRootCertificate
}

async function createCertificate(encoded: string): Promise<cert.X509Cert> {
  return cert.createX509Cert({
    data: decodeBase64(encoded),
    encodingFormat: cert.EncodingFormat.FORMAT_DER
  })
}

function encodeDerInteger(raw: Uint8Array): Uint8Array {
  let first = 0
  while (first < raw.length - 1 && raw[first] === 0) {
    first++
  }
  const needsLeadingZero = (raw[first] & 0x80) !== 0
  const valueLength = raw.length - first + (needsLeadingZero ? 1 : 0)
  const encoded = new Uint8Array(2 + valueLength)
  encoded[0] = 0x02
  encoded[1] = valueLength
  const valueOffset = needsLeadingZero ? 3 : 2
  for (let index = first; index < raw.length; index++) {
    encoded[valueOffset + index - first] = raw[index]
  }
  return encoded
}

/** JWS ES256 uses fixed-width r||s; Crypto Architecture Kit expects ASN.1 DER. */
function jwsSignatureToDer(rawSignature: Uint8Array): Uint8Array {
  if (rawSignature.length !== 64) {
    throw new Error('invalid ES256 signature length')
  }
  const r = encodeDerInteger(rawSignature.slice(0, 32))
  const s = encodeDerInteger(rawSignature.slice(32, 64))
  const result = new Uint8Array(2 + r.length + s.length)
  result[0] = 0x30
  result[1] = r.length + s.length
  result.set(r, 2)
  result.set(s, 2 + r.length)
  return result
}

async function verifyCertificateChain(x5c: string[]): Promise<cert.X509Cert> {
  if (x5c.length !== 3) {
    throw new Error('invalid IAP certificate chain length')
  }
  const leaf = await createCertificate(x5c[0])
  const intermediate = await createCertificate(x5c[1])
  const suppliedRoot = await createCertificate(x5c[2])
  const trustedRoot = await getTrustedRootCertificate()
  const suppliedRootEncoded = await suppliedRoot.getEncoded()
  const trustedRootEncoded = await trustedRoot.getEncoded()
  if (!bytesEqual(suppliedRootEncoded.data, trustedRootEncoded.data)) {
    throw new Error('IAP certificate root mismatch')
  }
  const chain = cert.createX509CertChain([leaf, intermediate, suppliedRoot])
  await chain.validate({
    trustAnchors: [{ CACert: trustedRoot }],
    keyUsage: [cert.KeyUsageType.KEYUSAGE_DIGITAL_SIGNATURE]
  })
  if (!hasRequiredLeafOid(leaf)) {
    throw new Error('IAP leaf certificate OID missing')
  }
  return leaf
}

function validatePurchasePayload(payload: PurchaseOrderPayload): void {
  if (payload.applicationId !== EXPECTED_APPLICATION_ID || payload.productId !== EXPECTED_PRODUCT_ID ||
    payload.productType !== EXPECTED_PRODUCT_TYPE) {
    throw new Error('IAP purchase identity mismatch')
  }
  if (!payload.purchaseToken || !payload.purchaseOrderId) {
    throw new Error('IAP purchase identifiers missing')
  }
  if (payload.purchaseOrderRevocationReasonCode !== undefined &&
    payload.purchaseOrderRevocationReasonCode.length > 0) {
    throw new Error('IAP purchase was revoked')
  }
  if (payload.environment !== 'NORMAL' && payload.environment !== 'SANDBOX') {
    throw new Error('invalid IAP purchase environment')
  }
  if (!BuildProfile.DEBUG && payload.environment !== 'NORMAL') {
    throw new Error('sandbox receipt rejected by release build')
  }
}

export async function verifyPurchaseData(purchaseDataJson: string): Promise<VerifiedPurchase> {
  const purchaseData = JSON.parse(purchaseDataJson) as PurchaseData
  if (purchaseData.type !== 1 || !purchaseData.jwsPurchaseOrder) {
    throw new Error('invalid non-consumable purchase data')
  }
  const jws = purchaseData.jwsPurchaseOrder
  const parts = jws.split('.')
  if (parts.length !== 3 || parts[0].length === 0 || parts[1].length === 0 || parts[2].length === 0) {
    throw new Error('invalid compact JWS')
  }
  const header = JSON.parse(decodeText(decodeBase64(parts[0], true))) as JwsHeader
  if (header.alg !== 'ES256' || header.typ !== 'JWT' || header.x5c === undefined) {
    throw new Error('unsupported IAP JWS header')
  }
  const leaf = await verifyCertificateChain(header.x5c)
  const keyGenerator = cryptoFramework.createAsyKeyGenerator('ECC256')
  const keyPair = keyGenerator.convertKeySync(leaf.getPublicKey().getEncoded(), null)
  const verifier = cryptoFramework.createVerify('ECC256|SHA256')
  await verifier.init(keyPair.pubKey)
  const verified = await verifier.verify({ data: encodeText(`${parts[0]}.${parts[1]}`) }, {
    data: jwsSignatureToDer(decodeBase64(parts[2], true))
  })
  if (!verified) {
    throw new Error('IAP JWS signature verification failed')
  }
  const payload = JSON.parse(decodeText(decodeBase64(parts[1], true))) as PurchaseOrderPayload
  validatePurchasePayload(payload)
  return {
    payload,
    jwsPurchaseOrder: jws
  }
}

export async function verifyCachedPurchaseJws(jws: string): Promise<VerifiedPurchase> {
  const purchaseData: PurchaseData = {
    type: 1,
    jwsPurchaseOrder: jws
  }
  return verifyPurchaseData(JSON.stringify(purchaseData))
}
