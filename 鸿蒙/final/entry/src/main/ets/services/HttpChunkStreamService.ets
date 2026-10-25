import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

// ========== 配置接口 ==========
export interface HttpChunkStreamConfig {
  url: string;
  chunkSizeBytes: number;
  chunkIntervalMs: number;
  maxFileSizeBytes: number;
}

// ========== 进度类 ==========
export class HttpChunkStreamProgress {
  public sentBytes: number;
  public totalBytes: number;
  public percent: number;

  constructor(sentBytes: number, totalBytes: number, percent: number) {
    this.sentBytes = sentBytes;
    this.totalBytes = totalBytes;
    this.percent = percent;
  }
}

// ========== 状态类型 ==========
export type HttpChunkStreamStatus = 'idle' | 'connecting' | 'streaming' | 'stopping' | 'done' | 'error';

// ========== 回调类（避免结构类型问题）==========
export class HttpChunkStreamCallbacks {
  public onStatus: (status: HttpChunkStreamStatus, message: string) => void;
  public onProgress: (progress: HttpChunkStreamProgress) => void;
  public onServerMessage: (data: string | ArrayBuffer) => void;

  constructor(
    onStatus: (status: HttpChunkStreamStatus, message: string) => void,
    onProgress: (progress: HttpChunkStreamProgress) => void,
    onServerMessage: (data: string | ArrayBuffer) => void
  ) {
    this.onStatus = onStatus;
    this.onProgress = onProgress;
    this.onServerMessage = onServerMessage;
  }
}

// ========== 可选回调类（如果某些回调不需要）==========
export class HttpChunkStreamCallbacksOptional {
  public onStatus?: (status: HttpChunkStreamStatus, message: string) => void;
  public onProgress?: (progress: HttpChunkStreamProgress) => void;
  public onServerMessage?: (data: string | ArrayBuffer) => void;

  constructor(
    onStatus?: (status: HttpChunkStreamStatus, message: string) => void,
    onProgress?: (progress: HttpChunkStreamProgress) => void,
    onServerMessage?: (data: string | ArrayBuffer) => void
  ) {
    this.onStatus = onStatus;
    this.onProgress = onProgress;
    this.onServerMessage = onServerMessage;
  }
}

// ========== 自定义错误类 ==========
class HttpChunkStreamError extends Error {
  public code: number;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
    this.name = 'HttpChunkStreamError';
  }
}

// ========== 内部消息类 ==========
class StartMessage {
  public type: string = 'start';
  public fileName: string;
  public fileSize: number;
  public mimeType: string;

  constructor(fileName: string, fileSize: number, mimeType: string) {
    this.fileName = fileName;
    this.fileSize = fileSize;
    this.mimeType = mimeType;
  }
}

class EndMessage {
  public type: string = 'end';
  public streamId: string;
  public fileName: string;
  public fileSize: number;
  public mimeType: string;

  constructor(streamId: string, fileName: string, fileSize: number, mimeType: string) {
    this.streamId = streamId;
    this.fileName = fileName;
    this.fileSize = fileSize;
    this.mimeType = mimeType;
  }
}

// ========== 构建器类 ==========
export class HttpChunkStreamServiceBuilder {
  private config: HttpChunkStreamConfig = {
    url: '',
    chunkSizeBytes: 1024 * 1024,
    chunkIntervalMs: 100,
    maxFileSizeBytes: 100 * 1024 * 1024
  };

  private onStatus: ((status: HttpChunkStreamStatus, message: string) => void) | undefined;
  private onProgress: ((progress: HttpChunkStreamProgress) => void) | undefined;
  private onServerMessage: ((data: string | ArrayBuffer) => void) | undefined;

  public setUrl(url: string): HttpChunkStreamServiceBuilder {
    this.config.url = url;
    return this;
  }

  public setChunkSizeBytes(size: number): HttpChunkStreamServiceBuilder {
    this.config.chunkSizeBytes = size;
    return this;
  }

  public setChunkIntervalMs(interval: number): HttpChunkStreamServiceBuilder {
    this.config.chunkIntervalMs = interval;
    return this;
  }

  public setMaxFileSizeBytes(maxSize: number): HttpChunkStreamServiceBuilder {
    this.config.maxFileSizeBytes = maxSize;
    return this;
  }

  public setOnStatus(callback: (status: HttpChunkStreamStatus, message: string) => void): HttpChunkStreamServiceBuilder {
    this.onStatus = callback;
    return this;
  }

  public setOnProgress(callback: (progress: HttpChunkStreamProgress) => void): HttpChunkStreamServiceBuilder {
    this.onProgress = callback;
    return this;
  }

  public setOnServerMessage(callback: (data: string | ArrayBuffer) => void): HttpChunkStreamServiceBuilder {
    this.onServerMessage = callback;
    return this;
  }

  public build(): HttpChunkStreamService {
    const callbacks: HttpChunkStreamCallbacksOptional = new HttpChunkStreamCallbacksOptional(
      this.onStatus,
      this.onProgress,
      this.onServerMessage
    );
    return new HttpChunkStreamService(this.config, callbacks);
  }
}

// ========== 主服务类 ==========
export class HttpChunkStreamService {
  private cfg: HttpChunkStreamConfig;
  private cb: HttpChunkStreamCallbacksOptional | null;
  private cancelRequested: boolean;
  private streamId: string;

  constructor(config: HttpChunkStreamConfig, callbacks: HttpChunkStreamCallbacksOptional | null) {
    this.cfg = config;
    this.cb = callbacks;
    this.streamId = this.generateStreamId();
    this.cancelRequested = false;
  }

  private generateStreamId(): string {
    const timestamp: string = Date.now().toString(36);
    const random: string = Math.random().toString(36).substring(2, 10);
    return timestamp + random;
  }

  public async start(fileUri: string, fileName: string, mimeType: string): Promise<void> {
    this.cancelRequested = false;

    if (this.cb?.onStatus) {
      this.cb.onStatus('connecting', '正在连接服务器...');
    }

    let file: fs.File | null = null;
    let total: number = 0;
    let buffer: ArrayBuffer | null = null;

    try {
      // 读取文件
      const stat: fs.Stat = await fs.stat(fileUri);
      total = stat.size;
      buffer = new ArrayBuffer(total);
      file = await fs.open(fileUri, fs.OpenMode.READ_ONLY);
      const readLen: number = await fs.read(file.fd, buffer);

      if (readLen !== total) {
        throw new Error('文件读取不完整');
      }

      if (total > this.cfg.maxFileSizeBytes) {
        const sizeMB: string = (total / 1024 / 1024).toFixed(2);
        const maxSizeMB: string = (this.cfg.maxFileSizeBytes / 1024 / 1024).toFixed(0);
        const errorMsg: string = `文件过大 (${sizeMB} MB)，请选择小于 ${maxSizeMB} MB 的视频`;

        if (this.cb?.onStatus) {
          this.cb.onStatus('error', errorMsg);
        }

        throw new HttpChunkStreamError(1001, errorMsg);
      }

      const sizeMB: string = (total / 1024 / 1024).toFixed(2);
      const statusMsg: string = `开始推送 (${sizeMB} MB)...`;

      if (this.cb?.onStatus) {
        this.cb.onStatus('streaming', statusMsg);
      }

      const encoder: util.TextEncoder = new util.TextEncoder();

      // 发送开始消息
      const startMsg: StartMessage = new StartMessage(fileName, total, mimeType);
      await this.sendJson(startMsg, encoder);

      // 分块发送数据
      let offset: number = 0;

      while (offset < total) {
        if (this.cancelRequested) {
          if (this.cb?.onStatus) {
            this.cb.onStatus('stopping', '已取消');
          }
          break;
        }

        const end: number = Math.min(offset + this.cfg.chunkSizeBytes, total);
        const chunk: ArrayBuffer = buffer.slice(offset, end);

        await this.sendChunk(chunk);

        offset = end;

        // 计算进度
        const percentValue: number = Math.floor((offset * 100) / total);
        const progressData: HttpChunkStreamProgress = new HttpChunkStreamProgress(offset, total, percentValue);

        if (this.cb?.onProgress) {
          this.cb.onProgress(progressData);
        }

        if (this.cfg.chunkIntervalMs > 0) {
          await this.sleep(this.cfg.chunkIntervalMs);
        }
      }

      // 发送结束消息
      if (!this.cancelRequested) {
        const endMsg: EndMessage = new EndMessage(this.streamId, fileName, total, mimeType);
        await this.sendJson(endMsg, encoder);

        const doneMsg: string = `推送完成 (${(total / 1024 / 1024).toFixed(2)} MB)`;
        if (this.cb?.onStatus) {
          this.cb.onStatus('done', doneMsg);
        }
      }

    } catch (error) {
      const err: BusinessError = error as BusinessError;
      console.error('HTTP 推送失败:', err.message);
      const errorMsg: string = `推送失败: ${err.message || '未知错误'}`;

      if (this.cb?.onStatus) {
        this.cb.onStatus('error', errorMsg);
      }

      throw new HttpChunkStreamError(1002, errorMsg);
    } finally {
      if (file !== null) {
        try {
          fs.close(file.fd);
        } catch (e) {
          // 忽略关闭错误
        }
      }
    }
  }

  public async stop(): Promise<void> {
    this.cancelRequested = true;
    if (this.cb?.onStatus) {
      this.cb.onStatus('idle', '已停止');
    }
  }

  // 辅助方法：将字符串转换为 ArrayBuffer
  private stringToArrayBuffer(str: string): ArrayBuffer {
    const textEncoder: util.TextEncoder = new util.TextEncoder();
    const uint8Array: Uint8Array = textEncoder.encodeInto(str);
    return uint8Array.buffer;
  }

  private async sendJson(msg: StartMessage | EndMessage, encoder: util.TextEncoder): Promise<void> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const jsonStr: string = JSON.stringify(msg);

      // 修复：使用 encodeInto 方法替代已弃用的 encode
      const body: ArrayBuffer = this.stringToArrayBuffer(jsonStr);

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'Content-Type': 'application/json'
        }
      };

      const response: http.HttpResponse = await request.request(this.cfg.url, options);

      if (response.responseCode !== 200 && response.responseCode !== 201) {
        console.warn(`服务器返回状态码: ${response.responseCode}`);
      }

      if (response.result !== undefined && this.cb?.onServerMessage) {
        const resultStr: string = response.result as string;
        this.cb.onServerMessage(resultStr);
      }

    } catch (error) {
      const err: BusinessError = error as BusinessError;
      console.error('发送 JSON 失败:', err.message);
      const errorMsg: string = `发送 JSON 失败: ${err.message || '未知错误'}`;
      throw new HttpChunkStreamError(1003, errorMsg);
    } finally {
      try {
        request.destroy();
      } catch (e) {
        // 忽略销毁错误
      }
    }
  }

  private async sendChunk(chunk: ArrayBuffer): Promise<void> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        extraData: chunk,
        expectDataType: http.HttpDataType.STRING,
        header: {
          'Content-Type': 'application/octet-stream'
        }
      };

      const response: http.HttpResponse = await request.request(this.cfg.url, options);

      if (response.responseCode !== 200 && response.responseCode !== 201) {
        console.warn(`发送数据块失败，状态码: ${response.responseCode}`);
      }

    } catch (error) {
      const err: BusinessError = error as BusinessError;
      console.error('发送数据块失败:', err.message);
      const errorMsg: string = `发送数据块失败: ${err.message || '未知错误'}`;
      throw new HttpChunkStreamError(1004, errorMsg);
    } finally {
      try {
        request.destroy();
      } catch (e) {
        // 忽略销毁错误
      }
    }
  }

  private async sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }
}