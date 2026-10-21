-- ===================================================
-- 数据库初始化脚本
-- 数据库：imagerecord
-- 表名：image_verify_record
-- 引擎：InnoDB，字符集：utf8mb4
-- 说明：由 Hibernate 实体 ImageVerifyRecord 反推生成
-- ===================================================

CREATE DATABASE IF NOT EXISTS imagerecord
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_general_ci;

USE imagerecord;

DROP TABLE IF EXISTS image_verify_record;

CREATE TABLE image_verify_record (
    id          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    device_id   VARCHAR(255)  DEFAULT NULL     COMMENT '设备标识（鸿蒙端 deviceId）',
    image_path  VARCHAR(500)  DEFAULT NULL     COMMENT '图片在服务器本地的保存路径',
    clarity     DOUBLE        DEFAULT NULL     COMMENT '清晰度评分（OpenCV Laplacian 方差）',
    ai_type     VARCHAR(255)  DEFAULT NULL     COMMENT 'AI 分类结果（格式："状态分类 , 等级判定"，需人工确认实际存储内容）',
    ai_status   INT           DEFAULT NULL     COMMENT 'AI 判定状态：0-不合格，1-合格 （代码中当前固定为 1，需人工确认）',
    create_time DATETIME      DEFAULT NULL     COMMENT '记录创建时间',
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='图像验证检测记录表';
