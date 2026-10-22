"""AI 侧车人脸识别与边界逻辑测试。"""

import asyncio
import io
import unittest
from unittest.mock import patch

import app
from fastapi import HTTPException
from PIL import Image
from pydantic import Field, ValidationError, create_model


class _FakeUploadFile:
    """模拟 FastAPI UploadFile 的分块读取行为。"""

    def __init__(self, data: bytes, headers: dict | None = None):
        self._data = data
        self._offset = 0
        self.headers = headers or {}

    async def read(self, size: int = -1) -> bytes:
        if self._offset >= len(self._data):
            return b""
        chunk = self._data[self._offset:self._offset + size]
        self._offset += len(chunk)
        return chunk


class ImageBoundaryTest(unittest.TestCase):
    """验证上传图片读取的字节与解码边界。"""

    @staticmethod
    def png_bytes(width: int = 32, height: int = 32) -> bytes:
        buffer = io.BytesIO()
        Image.new("RGB", (width, height)).save(buffer, format="PNG")
        return buffer.getvalue()

    def test_read_bounded_image_accepts_valid_image(self):
        """正常编码且尺寸合规的图片原样返回。"""
        data = self.png_bytes()

        result = asyncio.run(app._read_bounded_image(_FakeUploadFile(data)))

        self.assertEqual(data, bytes(result))

    def test_read_bounded_image_rejects_empty_upload(self):
        """空上传返回 400。"""
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(app._read_bounded_image(_FakeUploadFile(b"")))
        self.assertEqual(400, ctx.exception.status_code)

    def test_read_bounded_image_rejects_oversized_content_length(self):
        """content-length 超限时返回 413。"""
        data = self.png_bytes()
        headers = {"content-length": str(app.MAX_IMAGE_BYTES + 1)}

        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(app._read_bounded_image(_FakeUploadFile(data, headers)))
        self.assertEqual(413, ctx.exception.status_code)

    def test_read_bounded_image_rejects_non_image_bytes(self):
        """非图片字节返回 400 解码错误。"""
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(app._read_bounded_image(_FakeUploadFile(b"not-an-image")))
        self.assertEqual(400, ctx.exception.status_code)

    def test_pillow_pixel_limit_matches_service_limit(self):
        """Pillow 的解压炸弹阈值必须与服务上限一致。"""
        self.assertEqual(app.MAX_IMAGE_PIXELS, Image.MAX_IMAGE_PIXELS)

    def test_read_bounded_image_maps_decompression_bomb_to_413(self):
        """Pillow 炸弹异常按像素超限返回 413，而不是误判为损坏图片。"""
        with patch.object(
            app,
            "_verify_image_bounds",
            side_effect=Image.DecompressionBombError("too many pixels"),
        ):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(app._read_bounded_image(_FakeUploadFile(self.png_bytes())))
        self.assertEqual(413, ctx.exception.status_code)

    def test_read_bounded_image_rejects_dimensions_over_limit(self):
        """像素总数超限返回 413。"""
        data = self.png_bytes(32, 32)

        with patch.object(app, "MAX_IMAGE_PIXELS", 16):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(app._read_bounded_image(_FakeUploadFile(data)))
        self.assertEqual(413, ctx.exception.status_code)


class FaceOnlyAnalysisTest(unittest.TestCase):
    """验证人脸专用镜像的结构化兼容行为。"""

    def test_content_analysis_keeps_contract_without_scene_or_subject_models(self):
        """精简模式保留响应结构，但不生成场景或主体观察项。"""
        result = app._analyze_content_sync(b"unused")

        self.assertEqual(2, result.schema_version)
        self.assertEqual("face-recognition-v1", result.pipeline_version)
        self.assertEqual([], result.observations)

    def test_legacy_scene_labels_are_empty_for_face_only_analysis(self):
        """旧场景接口转换精简模式响应时返回空标签。"""
        result = app.ContentAnalysis(
            schemaVersion=2,
            pipelineVersion="face-recognition-v1",
            observations=[],
        )

        self.assertEqual([], app._legacy_scene_labels(result))

    def test_health_exposes_content_analysis_readiness_flag(self):
        """内容分析能力必须显式声明为不可用，后端据此跳过空桩上传。"""
        response = asyncio.run(app.health())
        self.assertFalse(response["content_analysis"])
        self.assertFalse(response["content_analysis_ready"])

    def test_ready_requires_only_face_recognition_model(self):
        """就绪检查只依赖人脸模型，不要求已移除的内容模型。"""
        complete_face_app = type(
            "CompleteFaceApp",
            (),
            {"models": {"detection": object(), "recognition": object()}},
        )()
        with patch.object(app, "face_app", complete_face_app):
            response = asyncio.run(app.ready())
        self.assertEqual("ready", response["status"])
        self.assertFalse(response["content_analysis"])

        incomplete_face_app = type("IncompleteFaceApp", (), {"models": {"detection": object()}})()
        with patch.object(app, "face_app", incomplete_face_app):
            with self.assertRaises(HTTPException) as incomplete:
                asyncio.run(app.ready())
        self.assertEqual(503, incomplete.exception.status_code)

        with patch.object(app, "face_app", None):
            with self.assertRaises(HTTPException) as not_ready:
                asyncio.run(app.ready())
        self.assertEqual(503, not_ready.exception.status_code)

    def test_content_observation_keeps_namespaces_separate(self):
        """结构化观察项必须分别表达主体和场景。"""
        result = app.ContentAnalysis(
            schemaVersion=2,
            pipelineVersion="test",
            observations=[
                app.ContentObservation(
                    namespace="SUBJECT",
                    code="person",
                    confidence=0.9,
                    source="test-detector",
                ),
                app.ContentObservation(
                    namespace="SCENE",
                    code="scene_test",
                    confidence=0.8,
                    source="test-classifier",
                ),
            ],
        )

        self.assertEqual(2, len(result.observations))
        self.assertEqual("SUBJECT", result.observations[0].namespace)
        self.assertEqual("SCENE", result.observations[1].namespace)


class SidecarBoundaryTest(unittest.TestCase):
    """验证推理接口认证和聚类输入边界。"""

    def test_sidecar_token_is_required(self):
        """缺少或错误的共享密钥必须被拒绝。"""
        with patch.object(app, "SIDECAR_SECRET", "expected-secret"):
            with self.assertRaises(HTTPException) as missing:
                app._require_sidecar_token(None)
            with self.assertRaises(HTTPException) as invalid:
                app._require_sidecar_token("wrong-secret")

        self.assertEqual(401, missing.exception.status_code)
        self.assertEqual(401, invalid.exception.status_code)

    def test_sidecar_token_accepts_exact_secret(self):
        """正确共享密钥通过常量时间比较。"""
        with patch.object(app, "SIDECAR_SECRET", "expected-secret"):
            self.assertIsNone(app._require_sidecar_token("expected-secret"))

    def test_cluster_request_rejects_excessive_face_count(self):
        """聚类请求不能超过服务端硬上限。"""
        with patch.object(app, "MAX_CLUSTER_FACES", 1):
            constrained_model = create_model(
                "ConstrainedClusterRequest",
                embeddings=(list[list[float]], Field(max_length=1)),
            )
            with self.assertRaises(ValidationError):
                constrained_model(embeddings=[[0.0], [1.0]])


if __name__ == "__main__":
    unittest.main()
