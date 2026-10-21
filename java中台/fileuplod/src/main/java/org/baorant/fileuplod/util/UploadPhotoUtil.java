package org.baorant.fileuplod.util;



import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.IOException;
import java.util.UUID;

@Slf4j
@Component
public class UploadPhotoUtil {

    private String uploadpath = "D:/工作室/uploadphotos";

    public ResponseEntity<String> uploadPhoto(MultipartFile file) throws Exception {
        //1.效验文件是不是为空
        if (file.isEmpty()) {
            throw new Exception("上传文件为空");
        }
        //2.效验文件类型
        String originalFilename = file.getOriginalFilename();
        assert originalFilename != null; //强制效验如果为空直接报错
        String suffix = originalFilename.substring(originalFilename.lastIndexOf("."));
        if (!suffix.matches("\\.(jpg|jpeg|png|gif)$")) {
            return ResponseEntity.badRequest().body("上传失败:仅支持jpg/jpeg/jpeg/gif 格式图片");
        }
        //3.确保保存目录存在
        File saveDir = new File(uploadpath);
        if (!saveDir.exists()) {
            boolean success = saveDir.mkdirs();
            if (!success) {
                return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("上传失败：创建保存目录失败");
            }
        }


        //4.生成唯一文件名（不存在则创建）
        String newFileName = UUID.randomUUID().toString() + suffix;
        File saveFile = new File(saveDir, newFileName);

        //5.将文件写入本地电脑
        try {
            file.transferTo(saveFile);
            return ResponseEntity.ok("上传成功：文件保存路径" + saveFile.getAbsolutePath());
        } catch (IOException e) {
            e.printStackTrace();
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("上传失败：" + e.getMessage());
        }
    }
}