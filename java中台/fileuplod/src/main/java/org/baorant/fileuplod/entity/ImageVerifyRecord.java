package org.baorant.fileuplod.entity;

import jakarta.persistence.*;
import lombok.Data;
import java.time.LocalDateTime;

@Data
@Entity
@Table(name = "image_verify_record")
public class ImageVerifyRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String deviceId;      // 设备ID
    private String imagePath;     // 图片路径
    private Double clarity;       // 清晰度
    private String aiType;        // AI分类
    private Integer aiStatus;     // 0不合格 1合格
    private LocalDateTime createTime; // 创建时间
}