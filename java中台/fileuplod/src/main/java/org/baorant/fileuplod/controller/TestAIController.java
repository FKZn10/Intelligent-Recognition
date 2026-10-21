package org.baorant.fileuplod.controller;

import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.multipart.MultipartFile;

import java.util.Map;

@RestController
@RequestMapping("/test")
public class TestAIController {

    private final RestTemplate restTemplate = new RestTemplate();

    // 测试接口：上传一张图片，调用 Python AI，返回结果
    @PostMapping("/ai")
    public Map<String, Object> testAI(@RequestParam("file") MultipartFile file) {
        try {
            String pythonUrl = "http://10.214.230.238:5000/predict";

            // 封装成 form-data 格式，和 Python 完全匹配
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.MULTIPART_FORM_DATA);

            MultiValueMap<String, Object> form = new LinkedMultiValueMap<>();
            form.add("file", file.getResource());

            HttpEntity<MultiValueMap<String, Object>> request = new HttpEntity<>(form, headers);
            ResponseEntity<Map> response = restTemplate.postForEntity(pythonUrl, request, Map.class);

            System.out.println("✅ AI 返回结果：" + response.getBody());
            return response.getBody();

        } catch (Exception e) {
            e.printStackTrace();
            return Map.of("msg", "调用失败", "error", e.getMessage());
        }
    }
}