{
  "module": {
    "name": "entry",
    "type": "entry",
    "description": "$string:module_desc",
    "mainElement": "EntryAbility",
    "deviceTypes": [
      "phone"
    ],
    "deliveryWithInstall": true,
    "installationFree": false,
    "pages": "$profile:main_pages",
    // 👇 添加这行 - 请求网络权限
    "requestPermissions": [
      {
        "name": "ohos.permission.INTERNET"
      }
    ],
    "abilities": [
      {
        "name": "EntryAbility",
        "srcEntry": "./ets/entryability/EntryAbility.ets",
        "description": "$string:EntryAbility_desc",
        "icon": "$media:layered_image",
        "label": "$string:EntryAbility_label",
        "startWindowIcon": "$media:startIcon",
        "startWindowBackground": "$color:start_window_background",
        "exported": true,
        "skills": [
          {
            "entities": [
              "entity.system.home"
            ],
            "actions": [
              "ohos.want.action.home"
            ]
          }
        ]
      }
    ],
    "extensionAbilities": [
      {
        "name": "EntryBackupAbility",
        "srcEntry": "./ets/entrybackupability/EntryBackupAbility.ets",
        "type": "backup",
        "exported": false,
        "metadata": [
          {
            "name": "ohos.extension.backup",
            "resource": "$profile:backup_config"
          }
        ]
      }
    ],
    "metadata": [
      {
        "name": "ohos.software.networksecurity",
        "resource": "$profile:network_security_config"
      }
    ]
  },
}// 导入工具模块 - 提供文本编码等功能
import { util } from '@kit.ArkTS';
// 导入媒体库助手模块 - 用于访问相册和拍照功能
import { photoAccessHelper } from '@kit.MediaLibraryKit';
// 导入通用能力模块 - 提供 UIAbility 上下文等基础功能
import { common } from '@kit.AbilityKit';
// 导入文件系统模块 - 用于文件读写操作
import { fileIo as fs } from '@kit.CoreFileKit';
// 导入 HTTP 网络模块 - 用于发起网络请求
import { http } from '@kit.NetworkKit';
// 导入业务错误模块 - 提供统一的错误处理机制
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 拍照并获取图片文件 URI 的异步函数
 * @param context - UIAbility 上下文对象，用于启动系统相机
 * @returns Promise<string> - 返回图片的文件 URI 字符串
 */
async function takePhotoAndGetUri(context: common.UIAbilityContext): Promise<string> {
  // 返回一个 Promise 对象用于异步操作
  return new Promise<string>(async (resolve, reject) => {
    try {
      // 创建 PhotoViewPicker 实例 - 这是系统提供的照片选择器组件
      let photoPicker = new photoAccessHelper.PhotoViewPicker();

      // 配置拍照选项对象
      let options: photoAccessHelper.PhotoSelectOptions = {
        // 设置 MIME 类型为图片类型
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        // 设置最大选择数量为 1 张
        maxSelectNumber: 1,
        // 启用拍照功能 - 允许直接调用相机
        isPhotoTakingSupported: true
      };

      // 拉起系统的照片选择界面（包含拍照选项）
      let result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);

      // 判断结果是否有效 - 检查是否有返回的图片 URI
      if (result && result.photoUris && result.photoUris.length > 0) {
        // 获取第一张图片的 URI
        let uri = result.photoUris[0];
        // 在控制台输出成功日志
        console.info('拍照成功，图片 URI: ' + uri);
        // 解决 Promise - 返回图片 URI
        resolve(uri);
      } else {
        // 用户取消或没有返回图片时，拒绝 Promise 并抛出错误
        reject(new Error('用户取消拍照或拍照失败'));
      }
    } catch (error) {
      // 捕获异常并在控制台输出错误日志
      console.error('拍照失败：' + JSON.stringify(error));
      // 拒绝 Promise 并传递错误对象
      reject(error);
    }
  });
}

/**
 * 上传图片到服务器的异步函数
 * @param uri - 图片文件的 URI 路径
 * @param serverUrl - 服务器上传接口地址
 * @returns Promise<http.HttpResponse> - 返回 HTTP 响应对象
 */
async function uploadImage(uri: string, serverUrl: string): Promise<http.HttpResponse> {
  // 返回一个 Promise 对象用于异步操作
  return new Promise<http.HttpResponse>(async (resolve, reject) => {
    // 声明文件对象变量 - 初始化为 null
    let file: fs.File | null = null;
    // 声明 HTTP 请求对象变量 - 初始化为 null
    let request: http.HttpRequest | null = null;

    try {
      // 通过 URI 以只读模式打开文件
      file = await fs.open(uri, fs.OpenMode.READ_ONLY);

      // 获取文件的统计信息（大小、修改时间等）
      let stat = await fs.stat(uri);

      // 创建一个与文件大小相同的 ArrayBuffer 用于存储文件内容
      let buf = new ArrayBuffer(stat.size);

      // 将文件内容读取到缓冲区中
      await fs.read(file.fd, buf);

      // 创建 HTTP 请求实例
      request = http.createHttp();

      // 从 URI 中提取文件名 - 找到最后一个斜杠后的部分
      let fileName = uri.substring(uri.lastIndexOf('/') + 1);

      // 生成随机边界字符串 - 用于 multipart/form-data格式
      let boundary = '----WebKitFormBoundary' + Math.random().toString(36).substring(2);

      // 创建文本编码器实例 - 用于将字符串转换为字节数组
      let textEncoder = new util.TextEncoder();

      // 构建multipart/form-data 的请求头字符串
      let headerStr = '--' + boundary + '\r\n' +
        'Content-Disposition: form-data; name="file"; filename="' + fileName + '"\r\n' +
        'Content-Type: image/jpeg\r\n\r\n';

      // 构建multipart/form-data 的请求尾字符串
      let footerStr = '\r\n--' + boundary + '--\r\n';

      // 将请求头字符串编码为字节数组
      let headerBuf = textEncoder.encodeInto(headerStr);

      // 将文件缓冲区转换为 Uint8Array
      let fileBuf = new Uint8Array(buf);

      // 将请求尾字符串编码为字节数组
      let footerBuf = textEncoder.encodeInto(footerStr);

      // 计算合并后的总长度
      let totalLength = headerBuf.length + fileBuf.length + footerBuf.length;

      // 创建指定长度的 Uint8Array 用于存储完整的请求体
      let combinedData = new Uint8Array(totalLength);

      // 将请求头数据设置到合并数组的开头位置
      combinedData.set(headerBuf, 0);

      // 将文件数据设置到合并数组的中间位置（请求头之后）
      combinedData.set(fileBuf, headerBuf.length);

      // 将请求尾数据设置到合并数组的末尾位置（请求头 + 文件数据之后）
      combinedData.set(footerBuf, headerBuf.length + fileBuf.length);

      // 构建 HTTP 请求配置对象
      let requestOptions: http.HttpRequestOptions = {
        // 设置请求方法为 POST
        method: http.RequestMethod.POST,
        // 设置请求头
        header: {
          // 设置内容类型为 multipart/form-data 并指定边界
          'Content-Type': 'multipart/form-data; boundary=' + boundary,
          // 设置接受任意类型的响应
          'Accept': '*/*',
          // 设置请求体长度
          'Content-Length': totalLength.toString()
        },
        // 设置请求体数据（二进制缓冲区）
        extraData: combinedData.buffer,
        // 期望返回的数据类型为字符串
        expectDataType: http.HttpDataType.STRING,
      };

      // 发起 HTTP POST 请求并等待响应
      let response = await request.request(serverUrl, requestOptions);

      // 判断响应状态码是否为成功（200 或 201）
      if (response.responseCode === 200 || response.responseCode === 201) {
        // 输出成功日志
        console.info('上传成功，服务器返回：' + response.result);
        // 解决 Promise - 返回响应对象
        resolve(response);
      } else {
        // 状态码不是成功状态时，输出错误日志
        console.error('上传失败，HTTP 状态码：' + response.responseCode);
        // 拒绝 Promise 并抛出带状态码的错误
        reject(new Error(`上传失败，状态码：${response.responseCode}`));
      }
    } catch (error) {
      // 将错误转换为 BusinessError 类型
      let err = error as BusinessError;
      // 输出异常日志
      console.error('上传异常：' + err.message);
      // 拒绝 Promise 并传递错误对象
      reject(error);
    } finally {
      // 最终清理代码块 - 无论成功失败都会执行

      // 如果文件对象存在则关闭它
      if (file) {
        // 关闭文件描述符释放资源
        fs.close(file.fd);
      }
      // 如果 HTTP 请求对象存在则销毁它
      if (request) {
        // 销毁 HTTP 请求释放资源
        request.destroy();
      }
    }
  });
}

// 使用@Entry 装饰器标记这是页面的入口组件
@Entry
// 使用@Component 装饰器标记这是一个自定义组件
@Component
// 定义 Index 结构体组件
struct Index {
  // 定义状态变量 message - 显示当前操作状态文本
  @State message: string = '点击按钮拍照并上传';

  // 定义状态变量 isLoading - 标识是否正在加载中
  @State isLoading: boolean = false;

  // 定义状态变量 imageUri - 存储已拍摄图片的 URI
  @State imageUri: string = '';

  // 定义私有成员变量 serverUrl - 服务器上传接口地址
  // private serverUrl: string = 'http://10.149.231.234:8085/api/file/upload/photo';
  private serverUrl: string = 'http://10.149.231.234:8085/api/upload/';
  // build 方法 - 构建 UI 界面的核心方法
  build() {
    // 创建水平布局容器 Row
    Row() {
      // 创建垂直布局容器 Column
      Column() {
        // 显示标题文本
        Text('拍照上传示例')
          .fontSize(24)              // 设置字体大小为 24
          .fontWeight(FontWeight.Bold) // 设置字体粗细为粗体
          .margin({ top: 30, bottom: 20 }) // 设置上下外边距

        // 显示状态文本 - 绑定到 message 变量
        Text(this.message)
          .fontSize(18)                    // 设置字体大小为 18
          .fontColor(this.isLoading ? Color.Gray : Color.Black) // 加载中显示灰色，否则黑色
          .margin({ top: 10, bottom: 10 }) // 设置上下外边距
          .textAlign(TextAlign.Center)     // 设置文本居中对齐
          .width('90%')                    // 设置宽度为 90%

        // 条件渲染 - 当有图片 URI 时显示
        if (this.imageUri) {
          // 显示图片 URI 文本
          Text('图片 URI: ' + this.imageUri)
            .fontSize(12)                          // 设置字体大小为 12
            .fontColor(Color.Gray)                 // 设置字体颜色为灰色
            .margin({ bottom: 20 })                // 设置下外边距
            .maxLines(2)                           // 最多显示 2 行
            .textOverflow({ overflow: TextOverflow.Ellipsis }) // 超出显示省略号
            .width('90%')                          // 设置宽度为 90%
        }

        // 条件渲染 - 当加载中时显示进度条
        if (this.isLoading) {
          // 显示加载进度组件
          LoadingProgress()
            .width(50)       // 设置宽度为 50
            .height(50)      // 设置高度为 50
            .margin(30)      // 设置外边距为 30
            .color(Color.Blue) // 设置颜色为蓝色
        }

        // 创建按钮组件
        Button(this.isLoading ? '处理中...' : '拍照并上传') // 根据加载状态显示不同文本
          .width(220)                                    // 设置宽度为 220
          .height(50)                                    // 设置高度为 50
          .fontSize(18)                                  // 设置字体大小为 18
          .fontWeight(FontWeight.Bold)                   // 设置字体为粗体
          .backgroundColor(this.isLoading ? Color.Gray : Color.Blue) // 加载中灰色，否则蓝色
          .margin(20)                                    // 设置外边距为 20
          .enabled(!this.isLoading)                      // 加载中禁用按钮
          .onClick(() => {                               // 设置点击事件回调
            // 调用拍照上传方法
            this.performPhotoUpload();
          })
      }
      .width('100%')             // 设置 Column 宽度为 100%
      .height('100%')            // 设置 Column 高度为 100%
      .justifyContent(FlexAlign.Center) // 设置主轴方向居中
    }
    .height('100%')              // 设置 Row 高度为 100%
    .width('100%')               // 设置 Row 宽度为 100%
  }

  /**
   * 执行拍照上传的主逻辑方法
   * 这是一个异步方法，按顺序执行拍照和上传操作
   */
  async performPhotoUpload(): Promise<void> {
    // 设置加载状态为 true - 显示加载动画
    this.isLoading = true;

    // 更新状态文本提示用户正在启动相机
    this.message = '正在启动相机...';

    try {
      // 获取当前组件的 UIAbility 上下文对象
      let context = getContext(this) as common.UIAbilityContext;

      // 更新状态文本提示用户拍照
      this.message = '请拍照...';

      // 调用拍照函数并等待结果
      let uri = await takePhotoAndGetUri(context);

      // 将获取到的图片 URI 保存到状态变量
      this.imageUri = uri;

      // 更新状态文本提示拍照成功，准备上传
      this.message = '拍照成功，正在上传...';

      // 调用上传函数并等待服务器响应
      let response = await uploadImage(uri, this.serverUrl);

      // 上传成功后更新状态文本
      this.message = '上传成功！';

      // 在控制台输出服务器返回的响应内容
      console.info('服务器响应：' + response.result);

    } catch (error) {
      // 捕获异常并在控制台输出详细错误信息
      console.error('操作失败：' + JSON.stringify(error));

      // 根据错误类型设置不同的提示信息
      if (typeof error === 'string') {
        // 如果是字符串类型的错误，直接使用
        this.message = error;
      } else if (error instanceof Error) {
        // 如果是 Error 对象，使用其 message 属性
        this.message = error.message;
      } else {
        // 其他类型错误显示通用提示
        this.message = '操作失败，请重试';
      }
    } finally {
      // 无论成功或失败，最后都要重置加载状态
      this.isLoading = false;
    }
  }
}{
  "network-security-config": {
    "domain-config": [
      {
        "domains": [
          {
            "include-subdomains": true,
            "name": "10.149.231.234"
          }
        ],
        "cleartext-traffic-permitted": true
      }
    ],
    "cleartext-traffic-permitted": false
  }
}{
  "string": [
    {
      "name": "module_desc",
      "value": "module description"
    },
    {
      "name": "EntryAbility_desc",
      "value": "description"
    },
    {
      "name": "EntryAbility_label",
      "value": "label"
    },
    {
      "name": "permission_internet_reason",
      "value": "需要访问网络以上传图片"
    },
    {
      "name": "permission_camera_reason",
      "value": "需要使用相机进行拍照"
    },
    {
      "name": "permission_read_media_reason",
      "value": "需要读取媒体文件以获取拍摄的照片"
    },
    {
      "name": "permission_write_media_reason",
      "value": "需要写入媒体文件以保存拍摄的照片"
    }
  ]
}