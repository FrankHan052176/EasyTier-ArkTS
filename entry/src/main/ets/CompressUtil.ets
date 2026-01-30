import { buffer } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { Logger } from './util/Logger';

export async function compressStr(str: string): Promise<string> {
  try {
    let buf = buffer.from(str).buffer
    let outBuf = new ArrayBuffer(4000);
    let zip = zlib.createZipSync();
    let comp = await zip.compress2(outBuf, buf, zlib.CompressLevel.COMPRESS_LEVEL_BEST_COMPRESSION)
    let compressed = buffer.from(outBuf.slice(0, comp.destLen))
    let result = compressed.toString("base64url")
    Logger.debug("compressed:" + result, "CompressUtil")
    Logger.debug("length:" + result.length, "CompressUtil")
    return result
  } catch (e) {
    Logger.error("compressStr error: " + JSON.stringify(e), "CompressUtil")
    return ""
  }
}

export async function uncompressStr(compressed: string): Promise<string> {
  try {
    let outBuf2 = buffer.from(compressed, "base64url").buffer
    let arrayBufferOut2 = new ArrayBuffer(4000);
    let zip = zlib.createZipSync();
    let uncomp = await zip.uncompress2(arrayBufferOut2, outBuf2)
    let unzip = buffer.from(arrayBufferOut2.slice(0, uncomp.destLength)).toString()
    Logger.debug("uncompressed:" + unzip, "CompressUtil")
    Logger.debug("length:" + unzip.length, "CompressUtil")
    return unzip
  } catch (e) {
    Logger.error("uncompressStr error: " + JSON.stringify(e), "CompressUtil")
    return ""
  }
}