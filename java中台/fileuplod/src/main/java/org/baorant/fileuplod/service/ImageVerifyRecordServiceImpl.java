//package org.baorant.fileuplod.service;
//
//import jakarta.persistence.criteria.Predicate;
//import org.baorant.fileuplod.dao.ImageVerifyRecordServices;
//import org.baorant.fileuplod.entity.ImageVerifyRecord;
//import org.baorant.fileuplod.dao.ImageVerifyRecordRepository;
//import org.springframework.data.domain.Page;
//import org.springframework.data.domain.PageRequest;
//import org.springframework.data.domain.Sort;
//import org.springframework.data.jpa.domain.Specification;
//import org.springframework.stereotype.Service;
//
//import java.util.ArrayList;
//import java.util.List;
//
//@Service
//public class ImageVerifyRecordServiceImpl implements ImageVerifyRecordServices {
//
//    private final ImageVerifyRecordRepository repository;
//
//    public ImageVerifyRecordServiceImpl(ImageVerifyRecordRepository repository) {
//        this.repository = repository;
//    }
//
//    @Override
//    public Page<ImageVerifyRecord> findByPage(int current, int size) {
//        // 按创建时间倒序
//        PageRequest pageRequest = PageRequest.of(
//                current - 1,  // JPA 页码从 0 开始！
//                size,
//                Sort.by(Sort.Direction.DESC, "id")
//        );
//        return repository.findAll(pageRequest);
//    }
//
//    @Override
//    public Page<ImageVerifyRecord> findPage(
//            int current, int size,
//            Long id, String deviceId,
//            Double clarityMin, Double clarityMax,
//            String aiType, Integer aiStatus
//    ) {
//        PageRequest pageRequest = PageRequest.of(
//                current - 1,
//                size,
//                Sort.by(Sort.Direction.DESC, "id")
//        );
//
//        // 动态拼接查询条件
//        Specification<ImageVerifyRecord> spec = (root, query, cb) -> {
//            List<Predicate> list = new ArrayList<>();
//
//            if (id != null) {
//                list.add(cb.equal(root.get("id"), id));
//            }
//            if (deviceId != null && !deviceId.isEmpty()) {
//                list.add(cb.like(root.get("deviceId"), "%" + deviceId + "%"));
//            }
//            if (clarityMin != null) {
//                list.add(cb.greaterThanOrEqualTo(root.get("clarity"), clarityMin));
//            }
//            if (clarityMax != null) {
//                list.add(cb.lessThanOrEqualTo(root.get("clarity"), clarityMax));
//            }
//            if (aiType != null && !aiType.isEmpty()) {
//                list.add(cb.like(root.get("aiType"), "%" + aiType + "%"));
//            }
//            if (aiStatus != null) {
//                list.add(cb.equal(root.get("aiStatus"), aiStatus));
//            }
//
//            return cb.and(list.toArray(new Predicate[0]));
//        };
//
//        return repository.findAll(spec, pageRequest);
//    }
//}
