import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { WebSocketStreamPusher, WebSocketStreamPusherEvents } from './WebSocketStreamPusher';

export interface VideoFileStreamConfig {
  wsUrl: string;
  chunkSizeBytes: number;
  chunkIntervalMs: number;
  maxFileSizeBytes: number;
}

export interface VideoFileStreamProgress {
  sentBytes: number;
  totalBytes: number;
  percent: number;
}

export type VideoFileStreamStatus = 'idle' | 'connecting' | 'streaming' | 'stopping' | 'done' | 'error';

export interface VideoFileStreamCallbacks {
  onStatus?: (status: VideoFileStreamStatus, message: string) => void;
  onProgress?: (progress: VideoFileStreamProgress) => void;
  onServerMessage?: (data: string | ArrayBuffer) => void;
}

interface VideoStreamStartMessage {
  type: 'start';
  fileName: string;
  fileSize: number;
  mimeType: string;
}

interface VideoStreamEndMessage {
  type: 'end';
  fileSize: number;
}

interface FileReadResult {
  buffer: ArrayBuffer;
  size: number;
}

export class VideoFileStreamService {
  private readonly config: VideoFileStreamConfig;
  private readonly callbacks?: VideoFileStreamCallbacks;
  private pusher: WebSocketStreamPusher | null = null;
  private cancelRequested: boolean = false;

  constructor(config: VideoFileStreamConfig, callbacks?: VideoFileStreamCallbacks) {
    this.config = config;
    this.callbacks = callbacks;
  }

  private formatWsError(err: BusinessError): string {
    if (err && err.code === 200) {
      return 'WebSocket 握手失败：服务端返回 HTTP 200，该地址不是 WebSocket 服务，请检查 ws:// 地址';
    }
    return `WebSocket 错误: ${JSON.stringify(err)}`;
  }

  async start(fileUri: string): Promise<void> {
    const fileName = fileUri.substring(fileUri.lastIndexOf('/') + 1);
    const mimeType = 'video/mp4';
    if (this.pusher) {
      await this.stop();
    }

    this.cancelRequested = false;
    this.callbacks?.onStatus?.('connecting', '正在连接 WebSocket...');

    const wsEvents: WebSocketStreamPusherEvents = {
      onMessage: (data: string | ArrayBuffer) => {
        this.callbacks?.onServerMessage?.(data);
      },
      onClose: (code: number, reason: string) => {
        this.callbacks?.onStatus?.('idle', `连接已关闭(${code}) ${reason}`);
      },
      onError: (err: BusinessError) => {
        this.callbacks?.onStatus?.('error', this.formatWsError(err));
      }
    };

    const pusher: WebSocketStreamPusher = new WebSocketStreamPusher({ url: this.config.wsUrl });
    this.pusher = pusher;
    await pusher.connect(wsEvents);

    const readResult: FileReadResult = await this.readFileToBuffer(fileUri);
    const buffer: ArrayBuffer = readResult.buffer;
    const size: number = readResult.size;
    if (size > this.config.maxFileSizeBytes) {
      await this.stop();
      throw new Error(`文件过大(${size} bytes)，请缩短视频或降低清晰度后再试`);
    }

    this.callbacks?.onStatus?.('streaming', '开始推送...');

    const encoder: util.TextEncoder = util.TextEncoder.create();
    const startMsg: VideoStreamStartMessage = {
      type: 'start',
      fileName,
      fileSize: size,
      mimeType
    };
    await pusher.send(encoder.encode(JSON.stringify(startMsg)).buffer);

    const totalBytes: number = size;
    let sentBytes: number = 0;
    while (sentBytes < totalBytes) {
      if (this.cancelRequested) {
        this.callbacks?.onStatus?.('stopping', '已取消');
        break;
      }

      const end: number = Math.min(sentBytes + this.config.chunkSizeBytes, totalBytes);
      const chunk: ArrayBuffer = buffer.slice(sentBytes, end);
      await pusher.send(chunk);
      sentBytes = end;

      const percent: number = totalBytes > 0 ? Math.floor((sentBytes * 100) / totalBytes) : 0;
      const progress: VideoFileStreamProgress = { sentBytes, totalBytes, percent };
      this.callbacks?.onProgress?.(progress);

      if (this.config.chunkIntervalMs > 0) {
        await this.sleep(this.config.chunkIntervalMs);
      }
    }

    if (!this.cancelRequested) {
      const endMsg: VideoStreamEndMessage = { type: 'end', fileSize: size };
      await pusher.send(encoder.encode(JSON.stringify(endMsg)).buffer);
      this.callbacks?.onStatus?.('done', '推送完成');
    }
  }

  async stop(): Promise<void> {
    this.cancelRequested = true;
    const pusher: WebSocketStreamPusher | null = this.pusher;
    this.pusher = null;
    if (pusher) {
      await pusher.disconnect();
    }
    this.callbacks?.onStatus?.('idle', '已停止');
  }

  private async readFileToBuffer(uri: string): Promise<FileReadResult> {
    let file: fs.File | null = null;
    try {
      const stat: fs.Stat = await fs.stat(uri);
      const size: number = stat.size;
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      file = await fs.open(uri, fs.OpenMode.READ_ONLY);
      await fs.read(file.fd, buffer);
      return { buffer, size };
    } finally {
      if (file) {
        fs.close(file.fd);
      }
    }
  }

  private async sleep(ms: number): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), ms);
    });
  }
}
