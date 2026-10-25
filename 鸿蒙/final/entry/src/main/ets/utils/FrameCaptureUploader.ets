/*
 * 功能：从相机预览流中捕获 JPEG 帧，并通过 HTTP 上传到后端服务器
 * 路径：entry/src/main/ets/utils/FrameCaptureUploader.ets
 */
import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

export interface FrameUploadCallbacks {
  onResult?: (success: boolean, aiType: string, clarity: string, frameBase64?: string) => void;
  onError?: (err: string) => void;
}

// 定义响应数据接口（保持不变）
interface ResponseDataItem {
  success: boolean;
  aiType: string;
  clarity: string;
  frameImage?: string;
}

interface ResponseData {
  code: number;
  msg: string;
  data: ResponseDataItem;
}

// 【修复 5】新增：上传请求体接口，解决匿名对象报错
interface UploadRequestBody {
  deviceId: string;
  imageBase64: string;
}

export class FrameCaptureUploader {
  private imageReceiver: image.ImageReceiver | null = null;
  private uploadUrl: string;
  private deviceId: string;
  private callbacks?: FrameUploadCallbacks;
  private isCapturing: boolean = false;
  private isUploading: boolean = false;
  private lastUploadTime: number = 0;
  private uploadIntervalMs: number = 500;  // 提高间隔到500ms

  constructor(uploadUrl: string, deviceId: string, callbacks?: FrameUploadCallbacks) {
    this.uploadUrl = uploadUrl;
    this.deviceId = deviceId;
    this.callbacks = callbacks;
  }

  public async startCapture(previewWidth: number, previewHeight: number): Promise<string> {
    if (this.imageReceiver) {
      await this.stopCapture();
    }

    this.isCapturing = true;

    // 【修复1+2】移除无参createImageReceiver，补全正确参数，删除所有any断言
    // 鸿蒙ImageReceiver正确初始化方式：宽、高、格式、容量
    this.imageReceiver = image.createImageReceiver(
      previewWidth,
      previewHeight,
      image.ImageFormat.JPEG,
      1
    );

    // 【修复1】删除原any断言的属性赋值，通过createImageReceiver参数完成配置
    // 原错误代码：
    // (this.imageReceiver as any).size = { width: previewWidth, height: previewHeight };
    // (this.imageReceiver as any).format = image.ImageFormat.JPEG;
    // (this.imageReceiver as any).capacity = 1;
    // await (this.imageReceiver as any).init();

    this.imageReceiver.on('imageArrival', () => {
      if (this.isCapturing && !this.isUploading) {
        this.onImageArrival();
      }
    });

    const surfaceId = await this.imageReceiver.getReceivingSurfaceId();
    return surfaceId;
  }

  private async onImageArrival() {
    const now = Date.now();
    if (now - this.lastUploadTime < this.uploadIntervalMs) {
      return;
    }

    if (!this.imageReceiver || !this.isCapturing || this.isUploading) return;

    this.isUploading = true;

    try {
      const img = await this.imageReceiver.readNextImage();
      if (!img) {
        this.isUploading = false;
        return;
      }

      const component = await img.getComponent(image.ComponentType.JPEG);
      const arrayBuffer: ArrayBuffer = component.byteBuffer;
      img.release();

      await this.uploadFrameBase64(arrayBuffer);
      this.lastUploadTime = Date.now();
    } catch (err) {
      console.error(`捕获帧失败：${JSON.stringify(err)}`);
      this.callbacks?.onError?.(`帧处理失败：${JSON.stringify(err)}`);
    } finally {
      this.isUploading = false;
    }
  }

  // 使用 Base64 上传（避免 multipart 复杂性，同时保持兼容）
  private async uploadFrameBase64(jpegData: ArrayBuffer) {
    const uint8Array = new Uint8Array(jpegData);
    const base64Helper = new util.Base64Helper();
    // 【修复4】添加await，解决Promise<string>不能赋值给string的错误
    const base64: string = await base64Helper.encodeToString(uint8Array);

    // 【修复5】使用明确的UploadRequestBody类型，解决匿名对象报错
    const requestBody: UploadRequestBody = {
      deviceId: this.deviceId,
      imageBase64: base64
    };

    const httpRequest = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify(requestBody),
      connectTimeout: 5000,
      readTimeout: 10000
    };

    try {
      const response = await httpRequest.request(this.uploadUrl, options);
      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as ResponseData;
        if (result.code === 200) {
          const data = result.data;
          this.callbacks?.onResult?.(data.success, data.aiType, data.clarity, data.frameImage);
        } else {
          this.callbacks?.onError?.(result.msg);
        }
      } else {
        this.callbacks?.onError?.(`HTTP ${response.responseCode}`);
      }
    } catch (err) {
      const error = err as BusinessError;
      this.callbacks?.onError?.(`上传失败: ${error.message}`);
    } finally {
      httpRequest.destroy();
    }
  }

  public async stopCapture() {
    this.isCapturing = false;
    if (this.imageReceiver) {
      this.imageReceiver.off('imageArrival');
      // 【修复3】移除any断言，使用ImageReceiver官方release方法
      await this.imageReceiver.release();
      this.imageReceiver = null;
    }
  }
}