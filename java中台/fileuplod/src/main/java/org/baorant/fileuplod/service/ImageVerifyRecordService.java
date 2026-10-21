package org.baorant.fileuplod.service;

import jakarta.persistence.criteria.Predicate;
import org.baorant.fileuplod.entity.ImageVerifyRecord;
import org.baorant.fileuplod.dao.ImageVerifyRecordRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

@Service
public class ImageVerifyRecordService {

    @Autowired
    private ImageVerifyRecordRepository repository;

    public void save(ImageVerifyRecord record) {
        repository.save(record);
    }

//    public List<ImageVerifyRecord> list() {
//        return repository.findAll();
//    }

    public Page<ImageVerifyRecord> findPage(
            Integer current, Integer size,
            Long id, String deviceId,
            Double clarityMin, Double clarityMax,
            String aiType, Integer aiStatus) {

        // 强制打印后端接收到的参数，确认是否正确
        System.out.println("=== 后端接收到的搜索条件 ===");
        System.out.println("id: " + id);
        System.out.println("deviceId: " + deviceId);
        System.out.println("clarityMin: " + clarityMin);
        System.out.println("clarityMax: " + clarityMax);
        System.out.println("aiType: " + aiType);
        System.out.println("aiStatus: " + aiStatus);

        PageRequest pageRequest = PageRequest.of(
                current - 1,
                size,
                Sort.by(Sort.Direction.DESC, "id")
        );

        Specification<ImageVerifyRecord> spec = (root, query, cb) -> {
            List<Predicate> predicates = new ArrayList<>();

            if (id != null) {
                System.out.println("添加ID条件: id = " + id);
                predicates.add(cb.equal(root.get("id"), id));
            }
            if (deviceId != null && !deviceId.isEmpty()) {
                System.out.println("添加设备ID条件: deviceId like %" + deviceId + "%");
                predicates.add(cb.like(root.get("deviceId"), "%" + deviceId + "%"));
            }
            if (clarityMin != null) {
                System.out.println("添加清晰度下限: clarity >= " + clarityMin);
                predicates.add(cb.greaterThanOrEqualTo(root.get("clarity"), clarityMin));
            }
            if (clarityMax != null) {
                System.out.println("添加清晰度上限: clarity <= " + clarityMax);
                predicates.add(cb.lessThanOrEqualTo(root.get("clarity"), clarityMax));
            }
            if (aiType != null && !aiType.isEmpty()) {
                System.out.println("添加AI类型条件: aiType like %" + aiType + "%");
                predicates.add(cb.like(root.get("aiType"), "%" + aiType + "%"));
            }
            if (aiStatus != null) {
                System.out.println("添加状态条件: aiStatus = " + aiStatus);
                predicates.add(cb.equal(root.get("aiStatus"), aiStatus));
            }

            return cb.and(predicates.toArray(new Predicate[0]));
        };

        Page<ImageVerifyRecord> result = repository.findAll(spec, pageRequest);
        System.out.println("=== 查询结果 ===");
        System.out.println("总条数: " + result.getTotalElements());
        System.out.println("当前页数据: " + result.getContent().size());
        return result;
    }
}