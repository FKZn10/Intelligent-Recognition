package org.baorant.fileuplod.controller;

import jakarta.servlet.http.HttpServletResponse;
import org.baorant.fileuplod.entity.ImageVerifyRecord;
import org.baorant.fileuplod.service.ImageVerifyRecordService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.web.bind.annotation.*;

import java.io.File;
import java.io.FileInputStream;
import java.io.OutputStream;
import java.util.List;

@RestController
@RequestMapping("/api/image")
public class ImageRecordController {

    @Autowired
    private ImageVerifyRecordService imageVerifyRecordService;

    @GetMapping("/page")
    public Page<ImageVerifyRecord> getImagePage(
            @RequestParam(defaultValue = "1") Integer current,
            @RequestParam(defaultValue = "10") Integer size,

            // 搜索条件
            @RequestParam(required = false) Long id,
            @RequestParam(required = false) String deviceId,
            @RequestParam(required = false) Double clarityMin,
            @RequestParam(required = false) Double clarityMax,
            @RequestParam(required = false) String aiType,
            @RequestParam(required = false) Integer aiStatus
    ){
        return imageVerifyRecordService.findPage(
                current, size,
                id, deviceId,
                clarityMin, clarityMax,
                aiType, aiStatus
        );
    }

    // 获取图片
    @GetMapping("/image/{fileName:.+}")
    public void getImage(@PathVariable String fileName, HttpServletResponse response) {
        try {
            // 你的本地图片路径
            String filePath = "D:/studio/uploadphotos/" + fileName;
            File file = new File(filePath);

            FileInputStream fis = new FileInputStream(file);
            response.setContentType("image/jpeg");
            OutputStream os = response.getOutputStream();

            byte[] buffer = new byte[1024];
            int len;
            while ((len = fis.read(buffer)) != -1) {
                os.write(buffer, 0, len);
            }
            os.flush();
            fis.close();
            os.close();
        } catch (Exception e) {
            response.setStatus(404);
        }
    }
}