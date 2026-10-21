package org.baorant.fileuplod.controller;


import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.baorant.fileuplod.result.Result;
import org.baorant.fileuplod.util.ImageParseUtil;
import org.baorant.fileuplod.util.UploadPhotoUtil;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@Slf4j
@RestController
@RequestMapping("/api/file")
@RequiredArgsConstructor
public class FileUploadController {
    private final ImageParseUtil imageParseUtil;
    private final UploadPhotoUtil uploadPhotoUtil;

    @PostMapping("/upload-and-parse")
    public Result<String> uploadAndParseFile(@RequestParam("file")MultipartFile file){
        try{
            String content = imageParseUtil.parseImageContent(file);
            return Result.success(content);
        }catch (Exception e){
            return Result.fail(e.getMessage());
        }
    }

    @PostMapping("/upload/photo")
    public ResponseEntity<String> uploadPhoto(@RequestParam("file")MultipartFile file){
        try{
          ResponseEntity<String> savePath = uploadPhotoUtil.uploadPhoto(file);
          return ResponseEntity.status(HttpStatus.OK).body(savePath.getBody());
}catch (Exception e){
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }
}
