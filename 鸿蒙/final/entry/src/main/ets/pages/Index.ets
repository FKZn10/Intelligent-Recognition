import { camera } from '@kit.CameraKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import webSocket from '@ohos.net.webSocket';
import image from '@ohos.multimedia.image';

// ===================== 新增：适配后端返回格式的接口 ← 新增 =====================
interface DetectionResult {
  label?: string;
  defect?: string;
  position?: string;
  energy?: string; // 能效等级（后端返回）
  status?: string; // 检测状态（后端返回）
}
// ==============================================================================

@Entry
@Component
struct Index {
  @State previewStatus: string = '初始化中...';
  @State detectResult: string = '等待检测...';
  // ===================== 新增：单独存储后端返回的能效和状态 ← 新增 =====================
  @State energyLevel: string = '未检测'; // 能效等级
  @State detectStatus: string = '未检测'; // 检测状态
  // ==============================================================================
  private xComponentController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private captureSession: camera.CaptureSession | null = null;
  private currentCameraDevice: camera.CameraDevice | null = null;
  private ws: webSocket.WebSocket = webSocket.createWebSocket();
  private isWebSocketOpen: boolean = false;
  private imageReceiver: image.ImageReceiver | null = null;
  private deviceId: string = "device123";
  // 流控相关
  private sendQueue: ArrayBuffer[] = [];
  private isSending: boolean = false;
  private sendIntervalMs: number = 66; // 约15帧/秒
  private isStreaming: boolean = false;

  aboutToAppear() {
    this.checkPermissionsAndInit();
  }

  async checkPermissionsAndInit() {
    const permissions: Permissions[] = ['ohos.permission.CAMERA', 'ohos.permission.INTERNET'];
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      await atManager.requestPermissionsFromUser(getContext(this), permissions);
      this.initWebSocket();
    } catch (err) {
      console.error(`权限申请失败: ${JSON.stringify(err)}`);
      this.previewStatus = '权限被拒绝';
    }
  }

  initWebSocket() {
    const wsUrl = `ws://10.214.230.181:8080/websocket/verify/${this.deviceId}`;
    this.ws.connect(wsUrl, (err: BusinessError, value: boolean) => {
      if (err) {
        console.error(`WebSocket 连接失败: ${JSON.stringify(err)}`);
        this.detectResult = 'WebSocket 连接失败';
        return;
      }
      this.isWebSocketOpen = true;
      console.info('WebSocket 已连接');
      this.detectResult = '已连接检测服务';
    });

    // ===================== 核心修改：解析后端返回的 energy 和 status ← 新增 =====================
    this.ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (err) {
        console.error(`接收消息错误：${JSON.stringify(err)}`);
        return;
      }
      if (typeof value === 'string') {
        try {
          const result = JSON.parse(value) as DetectionResult;
          // 优先解析后端返回的能效和状态
          if (result.energy || result.status) {
            this.energyLevel = result.energy || '未知';
            this.detectStatus = result.status || '未知';
            // 更新展示文本，适配后端返回格式
            this.detectResult = `能效等级：${this.energyLevel} | 检测状态：${this.detectStatus}`;
          } else {
            // 兼容原有逻辑
            this.detectResult =
              `标签：${result.label || '未知'} | 缺陷：${result.defect || '无'} | 位置：${result.position || '未知'}`;
          }
        } catch (e) {
          console.error('解析消息失败:', e);
          this.detectResult = `接收消息：${value}`;
        }
      }
    });
    // ======================================================================================

    this.ws.on('close', () => {
      this.isWebSocketOpen = false;
      console.info('WebSocket 已关闭');
      // ===================== 新增：断开连接后重置状态 ← 新增 =====================
      this.energyLevel = '未检测';
      this.detectStatus = '未检测';
      this.detectResult = 'WebSocket已断开';
      // ==========================================================================
    });

    this.ws.on('error', (err: BusinessError) => {
      console.error(`WebSocket 错误: ${JSON.stringify(err)}`);
      this.isWebSocketOpen = false;
      // ===================== 新增：出错后重置状态 ← 新增 =====================
      this.energyLevel = '未检测';
      this.detectStatus = '未检测';
      this.detectResult = `WebSocket错误：${err.message}`;
      // ======================================================================
    });
  }

  onXComponentLoad = () => {
    const surfaceId = this.xComponentController.getXComponentSurfaceId();
    if (surfaceId && surfaceId.length > 0) {
      this.surfaceId = surfaceId;
      this.previewStatus = 'Surface 已获取，正在启动相机...';
      this.initCamera();
    } else {
      setTimeout(() => {
        const sid = this.xComponentController.getXComponentSurfaceId();
        if (sid) {
          this.surfaceId = sid;
          this.initCamera();
        } else {
          this.previewStatus = '无法获取预览表面';
        }
      }, 100);
    }
  };

  async initCamera() {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.cameraManager = camera.getCameraManager(context);
      const cameras = this.cameraManager.getSupportedCameras();
      if (cameras.length === 0) {
        this.previewStatus = '未找到摄像头';
        return;
      }
      this.currentCameraDevice =
        cameras.find(device => device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) || cameras[0];

      this.cameraInput = this.cameraManager.createCameraInput(this.currentCameraDevice);
      await this.cameraInput.open();

      const previewProfiles =
        this.cameraManager.getSupportedOutputCapability(this.currentCameraDevice, camera.SceneMode.NORMAL_PHOTO)
          .previewProfiles;
      if (!previewProfiles || previewProfiles.length === 0) {
        throw new Error('不支持预览');
      }
      const previewProfile = previewProfiles[0];

      // 预览输出（用于显示）
      this.previewOutput = this.cameraManager.createPreviewOutput(previewProfile, this.surfaceId);

      // 创建 ImageReceiver 用于获取预览帧（用于发送）
      const receiver = image.createImageReceiver(480, 480, image.ImageFormat.JPEG, 4);
      this.imageReceiver = receiver;
      const receiverSurfaceId = await receiver.getReceivingSurfaceId();
      // 创建第二个预览输出绑定到 ImageReceiver（用于采集）
      const frameOutput = this.cameraManager.createPreviewOutput(previewProfile, receiverSurfaceId);

      this.captureSession = this.cameraManager.createCaptureSession();
      await this.captureSession.beginConfig();
      this.captureSession.addInput(this.cameraInput);
      this.captureSession.addOutput(this.previewOutput);
      this.captureSession.addOutput(frameOutput);
      await this.captureSession.commitConfig();
      await this.captureSession.start();

      // 监听 ImageReceiver 的图片到达事件（总是消费帧）
      receiver.on('imageArrival', () => {
        this.consumeAndSendFrame(receiver);
      });

      this.previewStatus = '预览中，自动推流中...';
      // 自动开始推流
      this.startStream();
    } catch (err) {
      let e = err as BusinessError;
      console.error(`相机启动失败: ${e.message}`);
      this.previewStatus = `相机错误: ${e.message}`;
    }
  }

  // 消费帧，如果正在推流则加入发送队列
  private async consumeAndSendFrame(receiver: image.ImageReceiver) {
    try {
      const img = await receiver.readNextImage();
      // 1. 获取原始数据（YUV 格式）
      const component = await img.getComponent(image.ComponentType.JPEG);
      const yuvBuffer = component.byteBuffer;

      if (yuvBuffer && yuvBuffer.byteLength > 0) {
        if (this.isStreaming && this.isWebSocketOpen) {
          // 2. 从原始数据创建 ImageSource
          // 注意：sourceSize 必须与你创建 ImageReceiver 时的预览尺寸（480x480）完全一致
          const sourceOptions: image.SourceOptions = {
            sourceDensity: 0, // 使用默认密度
            sourcePixelFormat: image.PixelMapFormat.NV21, // 修改为 NV21 格式（Android Camera 预览常用格式）
            sourceSize: { width: 480, height: 480 }
          };
          const imageSource = image.createImageSource(yuvBuffer, sourceOptions);

          // 3. 解码为 PixelMap
          const decodeOptions: image.DecodingOptions = {
            editable: true,
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          };
          const pixelMap = await imageSource.createPixelMap(decodeOptions);

          // 4. 使用 ImagePacker 将 PixelMap 编码为 JPEG
          const packer = image.createImagePacker();
          const packOpts: image.PackingOption = {
            format: 'image/jpeg',
            quality: 70, // 质量 1-100，可以调整
          };
          const jpegBuffer = await packer.packToData(pixelMap, packOpts);

          if (jpegBuffer && jpegBuffer.byteLength > 0) {
            const copy = jpegBuffer.slice(0);
            this.sendQueue.push(copy);
            console.log(`捕获一帧，编码后大小 ${jpegBuffer.byteLength} 字节，队列长度 ${this.sendQueue.length}`);
            this.processSendQueue();
          } else {
            console.log(`编码失败，未生成 JPEG 数据`);
          }

          // 5. 释放所有资源
          pixelMap.release();
          packer.release();
          imageSource.release();
        } else {
          console.log(`帧已丢弃（推流状态：${this.isStreaming}, WebSocket: ${this.isWebSocketOpen}）`);
        }
      }
      img.release();
    } catch (err) {
      console.error(`消费帧失败：${JSON.stringify(err)}`);
    }
  }

  // 处理发送队列（串行 + 限流）
  private async processSendQueue() {
    if (this.isSending || !this.isWebSocketOpen || !this.isStreaming) {
      return;
    }
    this.isSending = true;
    while (this.sendQueue.length > 0 && this.isWebSocketOpen && this.isStreaming) {
      const buffer = this.sendQueue.shift();
      if (buffer) {
        try {
          await this.sendWsMessage(buffer);
          console.log(`发送一帧成功，大小 ${buffer.byteLength} 字节，队列剩余 ${this.sendQueue.length}`);
        } catch (err) {
          console.error(`发送失败: ${JSON.stringify(err)}`);
          this.stopStream(); // 发送失败，停止推流
          break;
        }
        // 限流
        await this.delay(this.sendIntervalMs);
      }
    }
    this.isSending = false;
  }

  private sendWsMessage(data: string | ArrayBuffer): Promise<void> {
    const isBinary = data instanceof ArrayBuffer;
    if (isBinary) {
      const bytes = new Uint8Array(data);
      const isValidJpeg = bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xD8;
      console.log(`发送数据 - 类型: 二进制(ArrayBuffer), 大小: ${data.byteLength}, 是否JPEG头(FF D8): ${isValidJpeg}`);
      if (!isValidJpeg && bytes.length >= 2) {
        console.warn(`警告: 数据不以FF D8开头，实际开头字节: 0x${bytes[0].toString(16)} 0x${bytes[1].toString(16)}`);
      }
    } else {
      console.log(`发送数据 - 类型: 字符串, 长度: ${data.length}`);
    }

    return new Promise((resolve, reject) => {
      this.ws.send(data, (err: BusinessError) => {
        if (err) {
          reject(err);
        } else {
          resolve();
        }
      });
    });
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  startStream() {
    if (!this.imageReceiver) {
      this.detectResult = '相机未就绪';
      return;
    }
    if (!this.isWebSocketOpen) {
      this.detectResult = 'WebSocket 未连接';
      return;
    }
    this.isStreaming = true;
    this.detectResult = '推流中...';
    this.previewStatus = '预览中，实时推流中...';
  }

  stopStream() {
    this.isStreaming = false;
    this.sendQueue = [];
    this.isSending = false;
    this.detectResult = '推流已停止';
    this.previewStatus = '预览中，已停止推流';
    // ===================== 新增：停止推流后重置状态 ← 新增 =====================
    this.energyLevel = '未检测';
    this.detectStatus = '未检测';
    // ==========================================================================
  }

  aboutToDisappear() {
    this.stopStream();
    if (this.imageReceiver) {
      this.imageReceiver.off('imageArrival');
      this.imageReceiver.release();
      this.imageReceiver = null;
    }
    if (this.ws) {
      this.ws.close();
    }
    if (this.captureSession) {
      this.captureSession.stop();
      this.captureSession.release();
    }
    if (this.previewOutput) {
      this.previewOutput.release();
    }
    if (this.cameraInput) {
      this.cameraInput.close();
    }
  }

  build() {
    Column() {
      Text('能效标签检测 - 实时视频流')
        .fontSize(20)
        .margin(10)

      XComponent({
        id: 'camera_preview',
        type: 'surface',
        controller: this.xComponentController
      })
        .width('100%')
        .height('60%')
        .onLoad(() => {
          this.onXComponentLoad();
        })

      Text(`预览状态: ${this.previewStatus}`)
        .fontSize(14)
        .margin(5)
        .fontColor(this.previewStatus.includes('预览中') ? Color.Green : Color.Red)

      // ===================== 优化：单独展示能效和状态（可选，更清晰） ← 新增 =====================
      Text(`能效等级: ${this.energyLevel}`)
        .fontSize(16)
        .margin(5)
        .fontColor(Color.Orange);

      Text(`检测状态: ${this.detectStatus}`)
        .fontSize(16)
        .margin(5)
        .fontColor(Color.Green);
      // ======================================================================================

      Text(`检测结果: ${this.detectResult}`)
        .fontSize(16)
        .margin(10)
        .fontColor(Color.Blue)

      Row() {
        Button('开始推流')
          .onClick(() => this.startStream())
          .margin(10)
        Button('停止推流')
          .onClick(() => this.stopStream())
          .margin(10)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}