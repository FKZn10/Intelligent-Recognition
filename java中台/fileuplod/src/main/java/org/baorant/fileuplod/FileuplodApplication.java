package org.baorant.fileuplod;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;

@SpringBootApplication
@EntityScan("org.baorant.fileuplod.entity")   // 扫描实体
@EnableJpaRepositories("org.baorant.fileuplod.dao") // 扫描仓库
public class FileuplodApplication {

    public static void main(String[] args) {
        SpringApplication.run(FileuplodApplication.class, args);
    }

}
