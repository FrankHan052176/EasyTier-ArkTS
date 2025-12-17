import { buffer } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { Logger } from './util/Logger';

export async function compressStr(str: string): Promise<string> {
  let buf = buffer.from(str).buffer
  let outBuf = new ArrayBuffer(4000);
  let zip = zlib.createZipSync();
  let comp = await zip.compress2(outBuf, buf, zlib.CompressLevel.COMPRESS_LEVEL_BEST_COMPRESSION)
  let compressed = buffer.from(outBuf.slice(0, comp.destLen))
  let result = compressed.toString("latin1")
  Logger.debug("compressed:" + result, "CompressUtil")
  Logger.debug("length:" + result.length, "CompressUtil")
  return result
}

export async function uncompressStr(compressed: string): Promise<string> {
  let outBuf2 = buffer.from(compressed, "latin1").buffer
  let arrayBufferOut2 = new ArrayBuffer(4000);
  let zip = zlib.createZipSync();
  let uncomp = await zip.uncompress2(arrayBufferOut2, outBuf2)
  let unzip = buffer.from(arrayBufferOut2.slice(0, uncomp.destLength)).toString()
  Logger.debug("uncompressed:" + unzip, "CompressUtil")
  Logger.debug("length:" + unzip.length, "CompressUtil")
  return unzip
}