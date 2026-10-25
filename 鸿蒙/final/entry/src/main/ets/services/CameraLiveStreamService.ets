import { camera } from '@kit.CameraKit';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs, ReadOptions } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { WebSocketStreamPusher } from './WebSocketStreamPusher';

// ========== 导出所有类型 ==========
export type CameraLiveStreamStatus = 'idle' | 'preparing' | 'streaming' | 'stopping' | 'error';

export interface CameraLiveStreamConfig {
  wsUrl: string;
  videoWidth: number;
  videoHeight: number;
  fps: number;
  videoBitrate: number;
  chunkSizeBytes: number;
  pollIntervalMs: number;
}

export class CameraLiveStreamProgress {
  sentBytes: number = 0;
  constructor(sentBytes: number) {
    this.sentBytes = sentBytes;
  }
}

export interface CameraLiveStreamCallbacks {
  onStatus?: (status: CameraLiveStreamStatus, message: string) => void;
  onProgress?: (progress: CameraLiveStreamProgress) => void;
  onServerMessage?: (data: string | ArrayBuffer) => void;
}

// ========== 内部类 ==========
class LiveStreamStartMessage {
  type: 'start' = 'start';
  container: 'mp4' = 'mp4';
  fileName: string;
  mimeType: 'video/mp4' = 'video/mp4';
  videoCodec: string;
  audioCodec: string;
  width: number;
  height: number;
  fps: number;
  constructor(fileName: string, width: number, height: number, fps: number) {
    this.fileName = fileName;
    this.videoCodec = 'video/avc';
    this.audioCodec = 'audio/mp4a-latm';
    this.width = width;
    this.height = height;
    this.fps = fps;
  }
}

class LiveStreamEndMessage {
  type: 'end' = 'end';
  finalSize: number;
  constructor(finalSize: number) {
    this.finalSize = finalSize;
  }
}

// ========== 主服务类 ==========
export class CameraLiveStreamService {
  private config: CameraLiveStreamConfig;
  private callbacks?: CameraLiveStreamCallbacks;

  private cancelRequested: boolean = false;
  private pusher: WebSocketStreamPusher | null = null;

  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private videoOutput: camera.VideoOutput | null = null;
  private videoSession: camera.VideoSession | null = null;

  private avRecorder: media.AVRecorder | null = null;
  private writeFile: fs.File | null = null;
  private readFile: fs.File | null = null;
  private videoUri: string = '';
  private fileName: string = '';

  private sentBytes: number = 0;
  private readOffset: number = 0;
  private readLoopPromise: Promise<void> | null = null;
  private isStreamingActive: boolean = false;

  constructor(config: CameraLiveStreamConfig, callbacks?: CameraLiveStreamCallbacks) {
    this.config = config;
    this.callbacks = callbacks;
  }

  private formatWsError(err: BusinessError): string {
    if (err && err.code === 200) {
      return 'WebSocket 握手失败：服务端返回 HTTP 200，该地址不是 WebSocket 服务，请检查 ws:// 地址';
    }
    return `WebSocket 错误: ${JSON.stringify(err)}`;
  }

  async start(context: common.UIAbilityContext, previewSurfaceId: string): Promise<void> {
    console.log("开始启动推流服务");

    await this.stop();

    this.cancelRequested = false;
    this.sentBytes = 0;
    this.readOffset = 0;
    this.isStreamingActive = false;
    if (this.callbacks?.onStatus) {
      this.callbacks.onStatus('preparing', '正在初始化相机与编码器...');
    }

    console.log("连接 WebSocket...");
    const pusher: WebSocketStreamPusher = new WebSocketStreamPusher({ url: this.config.wsUrl });
    this.pusher = pusher;

    try {
      await pusher.connect({
        onMessage: (data: string | ArrayBuffer) => {
          console.log("收到服务器消息");
          if (this.callbacks?.onServerMessage) {
            this.callbacks.onServerMessage(data);
          }
        },
        onClose: (code: number, reason: string) => {
          console.log("WebSocket 关闭:", code, reason);
          if (this.callbacks?.onStatus) {
            this.callbacks.onStatus('idle', `连接已关闭(${code}) ${reason}`);
          }
        },
        onError: (err: BusinessError) => {
          console.error("WebSocket 错误:", err);
          if (this.callbacks?.onStatus) {
            this.callbacks.onStatus('error', this.formatWsError(err));
          }
        }
      });
      console.log("WebSocket 连接成功");
    } catch (err) {
      console.error("WebSocket 连接失败:", err);
      throw new Error('WebSocket 连接失败');
    }

    try {
      console.log("准备相机和录制器...");
      await this.prepareCameraAndRecorder(context, previewSurfaceId);
      console.log("相机和录制器准备完成");

      console.log("发送开始消息...");
      await this.sendStartMessage();
      console.log("开始消息已发送");

      this.isStreamingActive = true;
      if (this.callbacks?.onStatus) {
        this.callbacks.onStatus('streaming', '推流中...');
      }

      console.log("开始读取和发送循环...");
      this.readLoopPromise = this.readAndSendLoop();

    } catch (e) {
      console.error("启动推流失败:", e);
      await this.cleanupResources();
      if (e instanceof Error) {
        throw new Error(e.message);
      }
      throw new Error('启动推流失败');
    }
  }

  async stop(): Promise<void> {
    console.log("停止推流服务");
    if (this.cancelRequested) {
      return;
    }
    this.cancelRequested = true;
    this.isStreamingActive = false;

    const loop: Promise<void> | null = this.readLoopPromise;
    this.readLoopPromise = null;

    try {
      if (this.callbacks?.onStatus) {
        this.callbacks.onStatus('stopping', '正在停止推流...');
      }
    } catch {
    }

    try {
      if (this.videoOutput) {
        await new Promise<void>((resolve: () => void) => {
          if (this.videoOutput) {
            this.videoOutput.stop(() => resolve());
          } else {
            resolve();
          }
        });
      }
    } catch {
    }

    try {
      if (this.avRecorder) {
        await this.avRecorder.stop();
      }
    } catch {
    }

    try {
      if (this.videoSession) {
        this.videoSession.stop();
      }
    } catch {
    }

    if (loop) {
      try {
        await loop;
      } catch {
      }
    }

    try {
      await this.flushRemainingBytes();
    } catch {
    }

    if (this.isStreamingActive && this.videoUri) {
      try {
        await this.sendEndMessage();
        console.log("结束消息已发送");
      } catch {
      }
    }

    await this.cleanupResources();

    if (this.callbacks?.onStatus) {
      this.callbacks.onStatus('idle', '已停止');
    }
    console.log("推流服务已停止");
  }

  private async cleanupResources(): Promise<void> {
    console.log("清理资源...");

    try {
      if (this.pusher) {
        await this.pusher.disconnect();
      }
    } catch {
    }
    this.pusher = null;

    try {
      if (this.readFile) {
        fs.close(this.readFile.fd);
      }
    } catch {
    }
    this.readFile = null;

    try {
      if (this.writeFile) {
        fs.closeSync(this.writeFile);
      }
    } catch {
    }
    this.writeFile = null;

    try {
      if (this.cameraInput) {
        this.cameraInput.close();
      }
    } catch {
    }
    this.cameraInput = null;

    try {
      if (this.previewOutput) {
        this.previewOutput.release();
      }
    } catch {
    }
    this.previewOutput = null;

    try {
      if (this.videoOutput) {
        this.videoOutput.release();
      }
    } catch {
    }
    this.videoOutput = null;

    try {
      if (this.videoSession) {
        this.videoSession.release();
      }
    } catch {
    }
    this.videoSession = null;

    this.avRecorder = null;
    this.cameraManager = null;
    this.videoUri = '';
    this.fileName = '';
  }

  private async prepareCameraAndRecorder(context: common.UIAbilityContext, previewSurfaceId: string): Promise<void> {
    console.log("获取相机管理器...");
    const cameraManager: camera.CameraManager = camera.getCameraManager(context);
    this.cameraManager = cameraManager;

    console.log("获取可用相机...");
    const cameraArray: Array<camera.CameraDevice> = cameraManager.getSupportedCameras();
    if (cameraArray.length <= 0) {
      throw new Error('未发现可用相机');
    }
    console.log("发现相机数量:", cameraArray.length);

    console.log("检查录像模式...");
    const sceneModes: Array<camera.SceneMode> = cameraManager.getSupportedSceneModes(cameraArray[0]);
    if (sceneModes.indexOf(camera.SceneMode.NORMAL_VIDEO) < 0) {
      throw new Error('设备不支持录像模式');
    }
    console.log("支持录像模式");

    console.log("获取相机输出能力...");
    const cameraOutputCap: camera.CameraOutputCapability =
      cameraManager.getSupportedOutputCapability(cameraArray[0], camera.SceneMode.NORMAL_VIDEO);
    const previewProfilesArray: Array<camera.Profile> = cameraOutputCap.previewProfiles;
    const videoProfilesArray: Array<camera.VideoProfile> = cameraOutputCap.videoProfiles;

    console.log("预览规格数量:", previewProfilesArray.length);
    console.log("视频规格数量:", videoProfilesArray.length);

    if (videoProfilesArray.length === 0) {
      throw new Error('没有可用的视频规格');
    }

    const videoProfile: camera.VideoProfile = videoProfilesArray[0];
    const actualWidth: number = videoProfile.size.width;
    const actualHeight: number = videoProfile.size.height;
    console.log(`使用视频规格: ${actualWidth}x${actualHeight}`);

    if (previewProfilesArray.length === 0) {
      throw new Error('没有可用的预览规格');
    }
    const previewProfile: camera.Profile = previewProfilesArray[0];

    const recorderProfile: media.AVRecorderProfile = {
      audioBitrate: 48000,
      audioChannels: 2,
      audioCodec: media.CodecMimeType.AUDIO_AAC,
      audioSampleRate: 48000,
      fileFormat: media.ContainerFormatType.CFT_MPEG_4,
      videoBitrate: this.config.videoBitrate,
      videoCodec: media.CodecMimeType.VIDEO_AVC,
      videoFrameWidth: actualWidth,
      videoFrameHeight: actualHeight,
      videoFrameRate: 30
    };

    console.log("创建视频文件...");
    const options: photoAccessHelper.CreateOptions = { title: Date.now().toString() };
    const accessHelper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
    const videoUri: string = await accessHelper.createAsset(photoAccessHelper.PhotoType.VIDEO, 'mp4', options);
    this.videoUri = videoUri;
    this.fileName = options.title + '.mp4';
    console.log("视频文件创建成功:", this.fileName);

    console.log("打开文件...");
    try {
      const writeFile: fs.File = fs.openSync(videoUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      this.writeFile = writeFile;
      console.log("文件打开成功，fd:", writeFile.fd);
    } catch (error) {
      console.error("文件打开失败:", error);
      throw new Error(`文件操作失败: ${error instanceof Error ? error.message : '权限不足'}`);
    }

    const recorderConfig: media.AVRecorderConfig = {
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
      videoSourceType: media.VideoSourceType.VIDEO_SOURCE_TYPE_SURFACE_YUV,
      profile: recorderProfile,
      url: `fd://${this.writeFile?.fd.toString()}`,
      rotation: 0
    };

    console.log("创建 AVRecorder...");
    const avRecorder: media.AVRecorder = await media.createAVRecorder();
    this.avRecorder = avRecorder;

    console.log("准备 AVRecorder...");
    await avRecorder.prepare(recorderConfig);
    console.log("AVRecorder 准备完成");

    const recorderSurfaceId: string = await avRecorder.getInputSurface();
    console.log("获取录制 Surface ID");

    console.log("创建视频输出...");
    const videoOutput: camera.VideoOutput = cameraManager.createVideoOutput(videoProfile, recorderSurfaceId);
    this.videoOutput = videoOutput;

    console.log("创建视频会话...");
    const videoSession: camera.VideoSession = cameraManager.createSession(camera.SceneMode.NORMAL_VIDEO) as camera.VideoSession;
    this.videoSession = videoSession;

    console.log("开始配置会话...");
    videoSession.beginConfig();

    console.log("创建相机输入...");
    const cameraInput: camera.CameraInput = cameraManager.createCameraInput(cameraArray[0]);
    this.cameraInput = cameraInput;
    await cameraInput.open();
    console.log("相机输入已打开");

    videoSession.addInput(cameraInput);
    console.log("已添加相机输入");

    console.log("创建预览输出...");
    const previewOutput: camera.PreviewOutput = cameraManager.createPreviewOutput(previewProfile, previewSurfaceId);
    this.previewOutput = previewOutput;
    videoSession.addOutput(previewOutput);
    console.log("已添加预览输出");

    videoSession.addOutput(videoOutput);
    console.log("已添加视频输出");

    console.log("提交配置...");
    await videoSession.commitConfig();
    console.log("配置已提交");

    console.log("启动会话...");
    await videoSession.start();
    console.log("会话已启动");

    console.log("启动视频输出...");
    await new Promise<void>((resolve: () => void, reject: (reason?: Error) => void) => {
      videoOutput.start((err: BusinessError) => {
        if (err) {
          console.error("videoOutput start error:", err.code, err.message);
          reject(new Error(`videoOutput start error: ${err.code} ${err.message}`));
          return;
        }
        console.log("视频输出已启动");
        resolve();
      });
    });

    console.log("启动录制...");
    await avRecorder.start();
    console.log("录制已启动");

    // 延迟打开文件用于读取，避免文件锁定
    console.log("等待录制开始...");
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 1000));

    console.log("打开文件用于读取...");
    try {
      const readFile: fs.File = await fs.open(videoUri, fs.OpenMode.READ_ONLY);
      this.readFile = readFile;
      console.log("文件打开成功，用于读取");
    } catch (error) {
      console.error("文件读取打开失败:", error);
      throw new Error(`文件读取操作失败: ${error instanceof Error ? error.message : '权限不足'}`);
    }
    console.log("CameraLiveStream 准备完成");
  }

  private async sendStartMessage(): Promise<void> {
    const pusher: WebSocketStreamPusher | null = this.pusher;
    if (!pusher) {
      return;
    }
    const encoder: util.TextEncoder = util.TextEncoder.create();
    const msg: LiveStreamStartMessage = new LiveStreamStartMessage(
      this.fileName || 'live.mp4',
      this.config.videoWidth,
      this.config.videoHeight,
      this.config.fps
    );
    const jsonStr: string = JSON.stringify(msg);
    console.log("发送开始消息:", jsonStr);
    await pusher.send(encoder.encode(jsonStr).buffer);
  }

  private async sendEndMessage(): Promise<void> {
    const pusher: WebSocketStreamPusher | null = this.pusher;
    if (!pusher || !this.videoUri) {
      return;
    }
    try {
      const stat: fs.Stat = await fs.stat(this.videoUri);
      const encoder: util.TextEncoder = util.TextEncoder.create();
      const msg: LiveStreamEndMessage = new LiveStreamEndMessage(stat.size);
      const jsonStr: string = JSON.stringify(msg);
      console.log("发送结束消息:", jsonStr);
      await pusher.send(encoder.encode(jsonStr).buffer);
    } catch (err) {
      console.error("发送结束消息失败:", err);
    }
  }

  private async readAndSendLoop(): Promise<void> {
    const pusher: WebSocketStreamPusher | null = this.pusher;
    const readFile: fs.File | null = this.readFile;
    if (!pusher || !readFile) {
      return;
    }

    while (!this.cancelRequested) {
      const hasNewData: boolean = await this.sendAvailableBytesOnce();
      if (!hasNewData) {
        await this.sleep(this.config.pollIntervalMs);
      }
    }
  }

  private async flushRemainingBytes(): Promise<void> {
    while (true) {
      const hasNewData: boolean = await this.sendAvailableBytesOnce();
      if (!hasNewData) {
        break;
      }
    }
  }

  private async sendAvailableBytesOnce(): Promise<boolean> {
    const pusher: WebSocketStreamPusher | null = this.pusher;
    const readFile: fs.File | null = this.readFile;
    const uri: string = this.videoUri;
    if (!pusher || !readFile || !uri) {
      return false;
    }

    try {
      const stat: fs.Stat = await fs.stat(uri);
      const size: number = stat.size;
      if (size <= this.readOffset) {
        return false;
      }

      const toRead: number = Math.min(this.config.chunkSizeBytes, size - this.readOffset);
      const buf: ArrayBuffer = new ArrayBuffer(toRead);
      const readOptions: ReadOptions = { offset: this.readOffset, length: toRead };
      const readLen: number = fs.readSync(readFile.fd, buf, readOptions);
      if (readLen <= 0) {
        return false;
      }

      const payload: ArrayBuffer = readLen < toRead ? buf.slice(0, readLen) : buf;
      await pusher.send(payload);

      this.readOffset += readLen;
      this.sentBytes += readLen;
      const progress: CameraLiveStreamProgress = new CameraLiveStreamProgress(this.sentBytes);
      if (this.callbacks?.onProgress) {
        this.callbacks.onProgress(progress);
      }

      return true;
    } catch (err) {
      console.error("发送数据失败:", err);
      return false;
    }
  }

  private async sleep(ms: number): Promise<void> {
    await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), ms));
  }
}