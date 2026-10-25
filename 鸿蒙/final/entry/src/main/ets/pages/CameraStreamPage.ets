import camera from '@ohos.multimedia.camera';
import { BusinessError } from '@ohos.base';

@Entry
@Component
struct CameraPage {
  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private captureSession: camera.CaptureSession | null = null;
  private surfaceId: string = '';
  private isCameraInitialized: boolean = false;

  private xComponentController: XComponentController = new XComponentController();

  build() {
    Column() {
      XComponent({
        id: 'camera_preview',
        type: XComponentType.SURFACE,
        controller: this.xComponentController,
        libraryname: ''
      })
        .onLoad(() => {
          if (this.isCameraInitialized) {
            console.warn('Camera already initialized, skip');
            return;
          }
          this.surfaceId = this.xComponentController.getXComponentSurfaceId();
          console.info('XComponent surfaceId: ' + this.surfaceId);
          this.initCamera();
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  async initCamera() {
    if (this.isCameraInitialized) {
      return;
    }
    this.isCameraInitialized = true;

    try {
      // 1. 获取 CameraManager（必须传入 context）
      const context = getContext(this);
      this.cameraManager = camera.getCameraManager(context);
      if (!this.cameraManager) {
        console.error('getCameraManager failed');
        return;
      }

      // 2. 获取相机列表
      const cameraArray = await this.cameraManager.getSupportedCameras();
      let rearCamera = cameraArray.find(cam => cam.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK);
      if (!rearCamera && cameraArray.length > 0) {
        rearCamera = cameraArray[0];
      }
      if (!rearCamera) {
        console.error('No available camera');
        return;
      }

      // 3. 创建 CameraInput
      this.cameraInput = await this.cameraManager.createCameraInput(rearCamera);
      await this.cameraInput.open();

      // 4. 获取预览配置
      const previewProfiles = await this.cameraManager.getSupportedOutputCapability(rearCamera, camera.SceneMode.NORMAL_PHOTO);
      const previewProfile = previewProfiles.previewProfiles[0];
      if (!previewProfile) {
        console.error('No preview profile');
        return;
      }

      // 5. 【关键】只创建一次 PreviewOutput，使用 XComponent 的 surfaceId
      if (!this.surfaceId) {
        console.error('surfaceId is empty');
        return;
      }
      this.previewOutput = await this.cameraManager.createPreviewOutput(previewProfile, this.surfaceId);

      // 6. 创建 CaptureSession 并配置
      this.captureSession = await this.cameraManager.createCaptureSession();
      await this.captureSession.beginConfig();
      await this.captureSession.addInput(this.cameraInput);
      await this.captureSession.addOutput(this.previewOutput);   // 只添加一次
      await this.captureSession.commitConfig();
      await this.captureSession.start();

      console.info('Camera session started successfully');
    } catch (err) {
      let error = err as BusinessError;
      console.error(`initCamera failed: code ${error.code}, message ${error.message}`);
      this.isCameraInitialized = false;
    }
  }

  aboutToDisappear() {
    this.releaseCamera();
  }

  async releaseCamera() {
    try {
      if (this.captureSession) {
        await this.captureSession.stop();
        await this.captureSession.release();
        this.captureSession = null;
      }
      if (this.previewOutput) {
        await this.previewOutput.release();
        this.previewOutput = null;
      }
      if (this.cameraInput) {
        await this.cameraInput.close();
        this.cameraInput = null;
      }
      this.isCameraInitialized = false;
      console.info('Camera resources released');
    } catch (err) {
      console.error('releaseCamera error: ' + JSON.stringify(err));
    }
  }
}