package org.baorant.fileuplod.result;

import com.alibaba.fastjson.JSONObject;
import jakarta.websocket.*;
import jakarta.websocket.server.PathParam;
import jakarta.websocket.server.ServerEndpoint;
import org.baorant.fileuplod.util.VideoStreamProcessor;
import org.opencv.core.Mat;
import org.opencv.core.MatOfByte;
import org.opencv.imgcodecs.Imgcodecs;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

@Component
@ServerEndpoint("/websocket/verify/{deviceId}")
public class VerifyResultwebSocket {

    // 固定由配置类注入
    public static VideoStreamProcessor processor;

    public static void setProcessor(VideoStreamProcessor p) {processor = p;}

    private static final ConcurrentHashMap<String, Session> DEVICE_SESSIONS = new ConcurrentHashMap<>();
    private static final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(1);

//    static {
//        // 现在：定时模拟
//        scheduler.scheduleAtFixedRate(() -> {
//            for (String deviceId : DEVICE_SESSIONS.keySet()) {
//              sendMockAiResult(deviceId); // 模拟
//                  sendMockAiResult(deviceId, energy, status);
//            }
//        }, 0, 1000, TimeUnit.MILLISECONDS);
//    }

    // ========================
    // 现在：模拟 AI 返回
    // ========================
//    public static void sendMockAiResult(String deviceId) {
//        Session session = DEVICE_SESSIONS.get(deviceId);
//        if (session == null || !session.isOpen()) return;
//
//        try {
//            JSONObject obj = new JSONObject();
//            obj.put("energy", "二级");
//            obj.put("status", "正常");
//            session.getBasicRemote().sendText(obj.toString());
//        } catch (Exception e) {
//            System.err.println("模拟异常，请检查代码");
//        }
//    }

    // ========================
    // 未来：对接 Python AI
    // ========================
    //    public static void sendRealAiResult(String deviceId, String imagePath) {
//        try {
//            RestTemplate restTemplate = new RestTemplate();
//            String pythonUrl = "http://10.216.42.238:8000";
//
//            Map<String, String> params = new HashMap<>();
//            params.put("imagePath", imagePath);
//
//            Map<String, Object> aiResult = restTemplate.postForObject(pythonUrl, params, Map.class);
//
//            String energy = (String) aiResult.get("energy");
//            String status = (String) aiResult.get("status");
//
//            JSONObject obj = new JSONObject();
//            obj.put("energy", energy);
//            obj.put("status", status);
//
//            DEVICE_SESSIONS.get(deviceId).getBasicRemote().sendText(obj.toString());
//        } catch (Exception e) {
//            System.out.println("对接异常");
//        }
//    }

    public static void sendMockAiResult(String deviceId, String energy_level,String status) {
        System.out.println("🔔 sendMockAiResult called: deviceId=" + deviceId + ", status=" + status + ", energy=" + energy_level);
        Session session = DEVICE_SESSIONS.get(deviceId);
        if (session == null || !session.isOpen()) return;

        try {
            JSONObject obj = new JSONObject();
            obj.put("status", status); // 状态
            obj.put("energy_level", energy_level);  //能级
            session.getBasicRemote().sendText(obj.toString());
            System.out.println("✅ 结果已发送: " + obj.toString());
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
    // ===================== 连接成功 =====================
    @OnOpen
    public void onOpen(Session session, @PathParam("deviceId") String deviceId) {
        session.setMaxBinaryMessageBufferSize(1024 * 1024 * 10); // 扩大缓冲区
        DEVICE_SESSIONS.put(deviceId, session);
        System.out.println("✅ 设备[" + deviceId + "]已连接");
    }

    // ===================== 断开连接 =====================
    @OnClose
    public void onClose(@PathParam("deviceId") String deviceId) {
        DEVICE_SESSIONS.remove(deviceId);
        System.out.println("❌ 设备[" + deviceId + "]断开");
    }

    // ===================== 接收文本消息 =====================
    @OnMessage
    public void onMessage(String message, @PathParam("deviceId") String deviceId) {
        System.out.println("📝 收到设备消息：" + deviceId + " → " + message);
    }

    // ===================== 接收鸿蒙视频二进制流 =====================
    @OnMessage
    public void onBinary(byte[] data, @PathParam("deviceId") String deviceId) {
        System.out.println("onBinary begin");
        if (processor == null || data == null || data.length < 100) return;

        // --------------- 测试代码 ----------------
        System.out.println("数据总长度：" + data.length);

// 检查是不是 JPEG（JPEG 开头必须是 0xFF 0xD8）
        if (data.length >= 2) {
            int b1 = data[0] & 0xFF;
            int b2 = data[1] & 0xFF;
            System.out.println("JPEG 头部：" + b1 + ", " + b2);
            if (b1 == 0xFF && b2 == 0xD8) {
                System.out.println("✅ 这是标准 JPEG");
            } else {
                System.out.println("❌ 这不是 JPEG！头部错误！");
            }
        }

        Mat frame = null;
        try {
            frame = Imgcodecs.imdecode(new MatOfByte(data), Imgcodecs.IMREAD_COLOR);
            System.out.println("onBinary fame1: " + frame.empty());
            if (frame != null && !frame.empty()) {
                processor.processFrame(frame, deviceId);
            }
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            if (frame != null) frame.release();
        }
    }

    // ===================== 发送结果（你原有逻辑不变） =====================
    public static void sendVerifyResult(String deviceId, boolean success, String type, String base64) {
        Session session = DEVICE_SESSIONS.get(deviceId);
        if (session == null || !session.isOpen()) return;

        try {
            JSONObject obj = new JSONObject();
            obj.put("deviceId", deviceId);
            obj.put("verifySuccess", success);
            obj.put("aiType", type);
            obj.put("clarity", "合格");
            obj.put("frameImage", base64);
            session.getBasicRemote().sendText(obj.toString());
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    // ===================== 错误 =====================
    @OnError
    public void onError(Session session, Throwable error) {
        System.out.println("⚠️ WebSocket异常：" + error.getMessage());
        error.printStackTrace();
    }
}