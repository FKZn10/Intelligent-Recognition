package org.baorant.fileuplod.util;

import org.baorant.fileuplod.entity.ImageVerifyRecord;
import org.baorant.fileuplod.result.VerifyResultwebSocket;
import org.baorant.fileuplod.service.ImageVerifyRecordService;
import org.opencv.core.*;
import org.opencv.imgcodecs.Imgcodecs;
import org.opencv.imgproc.Imgproc;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;

import java.io.File;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

import static org.baorant.fileuplod.result.VerifyResultwebSocket.sendMockAiResult;

/**
 * 视频流处理工具：接收鸿蒙设备推送的视频流，截取帧并进行图片验证
 */
@Component
public class VideoStreamProcessor {

    // 初始化OpenCV
    static {
        System.loadLibrary(Core.NATIVE_LIBRARY_NAME);
        try {
            System.out.println("✅ OpenCV 加载成功");
        } catch (Exception e) {
            System.err.println("❌ OpenCV 加载失败：" + e.getMessage());
        }
    }

    @Autowired
    private ImageVerifyRecordService imageVerifyRecordService;

    // 调用Python AI
    private final RestTemplate restTemplate = new RestTemplate();

    // 图片保存路径
    private static final String SAVE_PATH = "D:/studio/uploadphotos/";

    private static final long SEND_INTERVAL = 1000;
    private long lastSendTime = 0;
    // python AI 接口地址
//    private static final String PYTHON_AI_URL = "http://10.216.42.238:8000";

    // =============================================
    // ✅ 【核心】处理鸿蒙 WebSocket 推送过来的视频帧
    // =============================================
    public void processFrame(Mat frame, String deviceId) {
        if (frame == null || frame.empty()) {
            System.out.println("⚠️ 帧为空，跳过处理");
            return;
        }

        // ===================== 【关键：1秒发送一次】 ====================


            // ========== 5 秒才处理一次 ==========
            long now = System.currentTimeMillis();
            if (now - lastSendTime < SEND_INTERVAL) {
                frame.release();
                return;
            }
            lastSendTime = now;

            try {
            // 1. 清晰度校验
            Mat gray = new Mat();
            Imgproc.cvtColor(frame, gray, Imgproc.COLOR_RGB2GRAY);
            double clarity = getClarity(gray);
            System.out.println("📊 帧清晰度：" + clarity);

            // 2. 保存图片
            new File(SAVE_PATH).mkdirs();
            String fileName = System.currentTimeMillis() + ".jpg";
            String fullPath = SAVE_PATH + fileName;
            boolean saveSuccess = Imgcodecs.imwrite(fullPath, frame);

            if (saveSuccess) {
                System.out.println("✅ 图片保存成功：" + fullPath);
//                saveToDatabase(deviceId, fullPath, clarity, "实时视频帧", true);
            }

            // 3. 【新增】调用 Python AI 进行图片验证
            String base64 = matToBase64(frame);
            Map<String, Object> aiResult = callPythonAIService(base64);

            boolean aiSuccess = (boolean) aiResult.getOrDefault("success", false);
//            String aiMsg = (String) aiResult.getOrDefault("msg", "无返回信息");
//            System.out.println("🤖 AI 验证结果：" + aiMsg);

            // ============== 这里获取 AI 返回给你的结果 ==============

                // 第一步：从根拿到 data 对象
                Map<String, Object> data = (Map<String, Object>) aiResult.get("data");
                // 第二步：从 data 里拿真正的结果
                if (data != null) {
                    String energy_level = (String) data.getOrDefault("energy_level", "二级");
                    String status = (String) data.getOrDefault("status", "正常");

                    System.out.println("🤖 AI 返回：energy_level=" + energy_level + "，status=" + status);
                    // 4. 保存记录（包含 AI 结果）
                    saveToDatabase(deviceId, fullPath, clarity, energy_level + " , " +status, aiSuccess);
                    sendMockAiResult(deviceId, energy_level, status);

            }

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    // =============================================
    // 【旧方法保留】处理视频流地址（RTSP/HTTP）
    // =============================================
//    public void processVideo(String streamUrl, String deviceId) {
//        // 这个方法你现在不用，保留兼容
//    }

    // =============================================
    // 清晰度计算
    // =============================================
    private double getClarity(Mat gray) {
        MatOfDouble mean = new MatOfDouble();
        MatOfDouble std = new MatOfDouble();
        Core.meanStdDev(gray, mean, std);
        return Math.pow(std.get(0, 0)[0], 2);
    }

    // =============================================
    // Mat转Base64
    // =============================================
    private String matToBase64(Mat frame) {
        MatOfByte mob = new MatOfByte();
        Imgcodecs.imencode(".jpg", frame, mob);
        return Base64.getEncoder().encodeToString(mob.toArray());
    }

    // =============================================
    // 【新增】调用 Python AI 接口
    // =============================================
    private Map<String, Object> callPythonAIService(String base64) {
        try {
//            HttpHeaders headers = new HttpHeaders();
//            headers.setContentType(MediaType.APPLICATION_JSON);
//
//            Map<String, String> request = new HashMap<>();
//            request.put("image", base64);
//
//            HttpEntity<Map<String, String>> entity = new HttpEntity<>(request, headers);
//            return restTemplate.postForObject(PYTHON_AI_URL, entity, Map.class);
//=======================================================================================
            // 1. Flask 地址（换成你 Python 电脑的局域网 IP）
            String pythonUrl = "http://10.190.189.238:5000/predict";

            // 1. 把 base64 转回 byte[]
            byte[] imageBytes = Base64.getDecoder().decode(base64);

            // 2. 构建 form-data 表单，模拟文件上传
            MultiValueMap<String, Object> formData = new LinkedMultiValueMap<>();
            formData.add("file", new ByteArrayResource(imageBytes) {
                @Override
                public String getFilename() {
                    return "frame.jpg"; // 必须给文件名，Flask 才认成文件
                }
            });

            // 3. 发送请求
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.MULTIPART_FORM_DATA);

            HttpEntity<MultiValueMap<String, Object>> requestEntity =
                    new HttpEntity<>(formData, headers);

            return restTemplate.postForObject(pythonUrl, requestEntity, Map.class);

        } catch (Exception e) {
            System.err.println("❌ AI 服务调用失败：" + e.getMessage());
            Map<String, Object> error = new HashMap<>();
            error.put("success", false);
            error.put("msg", "AI 服务异常：" + e.getMessage());
            return error;
        }
    }

    // =============================================
    // 数据库入库
    // =============================================
    private void saveToDatabase(String deviceId, String imagePath, double clarity, String aiType, boolean aiSuccess) {
        try {
            ImageVerifyRecord record = new ImageVerifyRecord();
            record.setDeviceId(deviceId);
            record.setImagePath(imagePath);
            record.setClarity(clarity);
            record.setAiType(aiType);
            record.setAiStatus(1);
            record.setCreateTime(LocalDateTime.now());
            imageVerifyRecordService.save(record);
            System.out.println("✅ 记录入库成功");
        } catch (Exception e) {
            System.err.println("❌ 数据库保存失败：");
        }
    }
}

