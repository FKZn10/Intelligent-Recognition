package org.baorant.fileuplod.dao;

import org.baorant.fileuplod.entity.ImageVerifyRecord;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;


public interface ImageVerifyRecordRepository extends JpaRepository<ImageVerifyRecord, Long>, JpaSpecificationExecutor<ImageVerifyRecord> {
}


