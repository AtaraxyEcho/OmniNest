package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileUploadPart;
import com.omninest.modules.file.domain.FileUploadSession;
import com.omninest.modules.file.domain.UploadStatus;
import com.omninest.modules.file.dto.CompleteFileUploadPartRequest;
import com.omninest.modules.file.repository.FileUploadPartRepository;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 完成请求里的分片补报：校验序号、回写 ETag 与完成状态，并回算会话进度。
 *
 * <p>批量补报不经过单分片确认的计数器，{@code uploadedParts} 必须按实际完成数重算，
 * 否则上传队列显示的进度会长期落后于服务端分片状态。</p>
 *
 * @author OmniNest
 */
final class UploadPartCompletion {
    private UploadPartCompletion() {
    }

    static void apply(
            FileUploadPartRepository partRepository,
            FileUploadSession session,
            List<CompleteFileUploadPartRequest> requestedParts
    ) {
        if (requestedParts == null || requestedParts.isEmpty()) {
            return;
        }
        Set<Integer> partNumbers = new HashSet<>();
        for (CompleteFileUploadPartRequest requestedPart : requestedParts) {
            if (requestedPart.partNumber() <= 0
                    || requestedPart.partNumber() > session.getTotalParts()) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "分片序号超出上传会话范围");
            }
            if (!partNumbers.add(requestedPart.partNumber())) {
                throw new BusinessException(ErrorCode.PARAM_ERROR, "分片序号重复");
            }
        }
        Map<Integer, FileUploadPart> partsByNumber = partRepository
                .findByUploadSessionIdOrderByPartNumber(session.getId())
                .stream()
                .collect(Collectors.toMap(FileUploadPart::getPartNumber, part -> part));
        List<FileUploadPart> toSave = new ArrayList<>();
        for (CompleteFileUploadPartRequest requestedPart : requestedParts) {
            FileUploadPart part = partsByNumber.get(requestedPart.partNumber());
            if (part == null) {
                throw new BusinessException(ErrorCode.FILE_UPLOAD_FAILED, "上传分片不存在");
            }
            part.setETag(normalizeETag(requestedPart.eTag()));
            part.setStatus(UploadStatus.COMPLETED.getValue());
            toSave.add(part);
        }
        partRepository.saveAll(toSave);
        session.setUploadedParts(Math.toIntExact(partsByNumber.values().stream()
                .filter(part -> UploadStatus.COMPLETED.getValue().equals(part.getStatus()))
                .count()));
    }

    static String normalizeETag(String rawETag) {
        String eTag = rawETag == null ? "" : rawETag.trim().replace("\"", "");
        if (eTag.isEmpty() || eTag.length() > 160) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "ETag 格式不合法");
        }
        return eTag;
    }
}
