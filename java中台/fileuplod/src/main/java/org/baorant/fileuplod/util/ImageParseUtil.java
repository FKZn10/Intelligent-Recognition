package org.baorant.fileuplod.util;

import com.google.zxing.*;
import com.google.zxing.client.j2se.BufferedImageLuminanceSource;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.qrcode.QRCodeReader;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.InputStream;


//二维码解析工具
@Slf4j
@Component
public class ImageParseUtil {
    /**
     * 解析图篇内容(仅二维码)
     * @param file 前端上传图片文件
     * @return 二维码内容
     */

    //MultipartFile 是文件上传接口的核心代码
    public String parseImageContent(MultipartFile file) throws Exception {
        //1.效验文件
        if (file.isEmpty()) {
            throw new Exception("上传的文件为空");
        }
        //2.如果效验文件不为空开始读取图片二维码解析
        try(InputStream inputStream = file.getInputStream()){  //读取文件内容
            BufferedImage image = ImageIO.read(inputStream);
            if(image == null){
                throw new Exception("不支持的图片格式");   //支持格式有jpg/jpeg/pog/gif/bmp/wbmp/tif格式
            }
            // ZXing核心解析逻辑
            LuminanceSource source = new BufferedImageLuminanceSource(image);  //预处理将格式转换方便识别
            BinaryBitmap bitmap = new BinaryBitmap(new HybridBinarizer(source));
            ResultPoint[] points;
            Result result = new QRCodeReader().decode(bitmap);

            return result.getText();
        }catch (NotFoundException e){
            throw new Exception("图片中未识别到二维码");
        }catch (Exception e){
            throw new Exception("文件解析失败："+e.getMessage());
        }
    }
}
