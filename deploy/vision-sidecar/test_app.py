"""AI 侧车 OCR、视觉档位与边界逻辑测试。"""

import asyncio
import io
import os
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np
from fastapi import HTTPException
from PIL import Image

import app


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
    """验证上传图片读取与解码边界。"""

    @staticmethod
    def png_bytes(width: int = 32, height: int = 32) -> bytes:
        buffer = io.BytesIO()
        Image.new("RGB", (width, height)).save(buffer, format="PNG")
        return buffer.getvalue()

    def test_read_image_bytes_accepts_valid_image(self):
        data = self.png_bytes()
        result = asyncio.run(app._read_image_bytes(_FakeUploadFile(data)))
        self.assertEqual(data, bytes(result))

    def test_read_image_bytes_rejects_empty_upload(self):
        with self.assertRaises(HTTPException) as context:
            asyncio.run(app._read_image_bytes(_FakeUploadFile(b"")))
        self.assertEqual(400, context.exception.status_code)

    def test_read_image_bytes_rejects_oversized_upload(self):
        data = self.png_bytes()
        with patch.object(app, "MAX_IMAGE_BYTES", 4):
            with self.assertRaises(HTTPException) as context:
                asyncio.run(app._read_image_bytes(_FakeUploadFile(data)))
        self.assertEqual(413, context.exception.status_code)

    def test_decode_rejects_non_image_bytes(self):
        with self.assertRaises(HTTPException) as context:
            app._decode_single_pass_bgr(b"not-an-image")
        self.assertEqual(400, context.exception.status_code)

    def test_pillow_pixel_limit_matches_service_limit(self):
        self.assertEqual(app.MAX_IMAGE_PIXELS, Image.MAX_IMAGE_PIXELS)

    def test_decode_maps_decompression_bomb_to_413(self):
        with patch.object(
            app.Image,
            "open",
            side_effect=Image.DecompressionBombError("too many pixels"),
        ):
            with self.assertRaises(HTTPException) as context:
                app._decode_single_pass_bgr(self.png_bytes())
        self.assertEqual(413, context.exception.status_code)

    def test_decode_rejects_dimensions_over_limit(self):
        data = self.png_bytes(32, 32)
        with patch.object(app, "MAX_IMAGE_PIXELS", 16):
            with self.assertRaises(HTTPException) as context:
                app._decode_single_pass_bgr(data)
        self.assertEqual(413, context.exception.status_code)

    def test_decode_downscales_long_side_before_bgr_conversion(self):
        data = self.png_bytes(1200, 600)
        with patch.object(app, "DECODE_MAX_SIDE", 600):
            bgr = app._decode_single_pass_bgr(data)
        self.assertEqual((300, 600, 3), bgr.shape)


class _FakeOcr:
    def __init__(self, result):
        self._result = result

    def __call__(self, _bgr):
        return self._result, [0.01]


class _FakeVisionInput:
    def __init__(self, name):
        self.name = name


class _FakeVisionSession:
    """最小 ONNX Runtime 会话替身，固定返回一个图像嵌入。"""

    def __init__(self, feature):
        self._feature = feature

    def get_inputs(self):
        return [_FakeVisionInput("image")]

    def run(self, _output_names, _inputs):
        return [np.stack([self._feature])]


class OcrGatingTest(unittest.TestCase):
    """验证 OCR 分档阈值与文本拼接。"""

    def test_small_boxes_require_higher_confidence(self):
        box_6px = [[0, 0], [6, 0], [6, 6], [0, 6]]
        box_10px = [[0, 20], [10, 20], [10, 30], [0, 30]]
        box_10px_ok = [[0, 40], [10, 40], [10, 50], [0, 50]]
        box_20px_ok = [[0, 60], [20, 60], [20, 80], [0, 80]]
        box_20px_low = [[0, 90], [20, 90], [20, 110], [0, 110]]
        fake = _FakeOcr([
            (box_6px, "tiny", 0.99),
            (box_10px, "small-low", 0.70),
            (box_10px_ok, "small-ok", 0.90),
            (box_20px_ok, "normal-ok", 0.70),
            (box_20px_low, "normal-low", 0.60),
        ])
        with patch.object(app.model_manager, "get_ocr", return_value=fake):
            text, line_count, area_ratio = app._run_gated_ocr(
                np.zeros((200, 200, 3), dtype=np.uint8)
            )

        self.assertEqual("small-ok\nnormal-ok", text)
        self.assertEqual(2, line_count)
        self.assertGreater(area_ratio, 0.0)

    def test_empty_ocr_result_returns_no_text(self):
        with patch.object(app.model_manager, "get_ocr", return_value=_FakeOcr(None)):
            text, line_count, area_ratio = app._run_gated_ocr(
                np.zeros((20, 20, 3), dtype=np.uint8)
            )
        self.assertIsNone(text)
        self.assertEqual(0, line_count)
        self.assertEqual(0.0, area_ratio)


class AnalysisPipelineTest(unittest.TestCase):
    """验证密集文本短路、skipOcr 与视觉档位分派。"""

    @staticmethod
    def image_bytes(width: int = 800, height: int = 450) -> bytes:
        buffer = io.BytesIO()
        Image.new("RGB", (width, height), color=(10, 20, 30)).save(buffer, format="PNG")
        return buffer.getvalue()

    def test_dense_text_short_circuits_visual_model(self):
        with patch.object(app, "_run_gated_ocr", return_value=("a\nb\nc\nd", 4, 0.2)):
            with patch.object(
                app,
                "_run_lightweight_visual_inference",
                side_effect=AssertionError("visual model must not run"),
            ):
                result = app._analyze_content_sync(
                    self.image_bytes(),
                    "TEXT_GRAPHIC",
                    False,
                )

        self.assertEqual("ppocr-v4-onnx-v1", result.ocr_pipeline_version)
        self.assertEqual("a\nb\nc\nd", result.ocr_text)
        self.assertEqual(1, len(result.observations))
        self.assertEqual("STYLE", result.observations[0].namespace)
        self.assertEqual("screenshot", result.observations[0].code)
        self.assertEqual("rapidocr-layout", result.observations[0].source)

    def test_skip_ocr_runs_visual_model_only(self):
        def add_visual_label(_bgr, scores):
            scores[("SUBJECT", "cat")] = (0.9, "mobileclip-s0-onnx")

        with patch.object(
            app,
            "_run_gated_ocr",
            side_effect=AssertionError("OCR must be skipped"),
        ):
            with patch.object(app, "_run_lightweight_visual_inference", side_effect=add_visual_label):
                result = app._analyze_content_sync(
                    self.image_bytes(),
                    "AUTO",
                    True,
                )

        self.assertIsNone(result.ocr_text)
        self.assertEqual(1, len(result.observations))
        self.assertEqual("SUBJECT", result.observations[0].namespace)
        self.assertEqual("cat", result.observations[0].code)

    def test_pipeline_version_contains_profile_model_state_and_ocr_version(self):
        self.assertIn(app.VISION_PROFILE, app.current_content_pipeline_version())
        self.assertIn(app._vision_model_state(app.VISION_PROFILE), app.current_content_pipeline_version())
        self.assertIn(app.OCR_PIPELINE_VERSION, app.current_content_pipeline_version())

    def test_vision_model_state_requires_all_profile_files(self):
        with patch.object(app.os.path, "isfile", return_value=True):
            self.assertEqual("ready", app._vision_model_state("lightweight"))
        with patch.object(app.os.path, "isfile", return_value=False):
            self.assertEqual("missing", app._vision_model_state("lightweight"))

    def test_mobileclip_preprocess_keeps_square_center_crop(self):
        bgr = np.zeros((200, 400, 3), dtype=np.uint8)
        mean = np.zeros((1, 1, 3), dtype=np.float32)
        std = np.ones((1, 1, 3), dtype=np.float32)
        tensor = app._preprocess_mobileclip_256(bgr, mean, std)
        self.assertEqual((1, 3, 256, 256), tensor.shape)
        self.assertEqual(np.float32, tensor.dtype)

    def test_mobileclip_preprocess_applies_asset_normalization(self):
        bgr = np.full((256, 256, 3), 255, dtype=np.uint8)
        mean = np.full((1, 1, 3), 0.5, dtype=np.float32)
        std = np.full((1, 1, 3), 0.5, dtype=np.float32)
        tensor = app._preprocess_mobileclip_256(bgr, mean, std)
        self.assertTrue(np.allclose(tensor, 1.0))

    def test_lightweight_scores_use_absolute_similarity(self):
        labels = [("SUBJECT", "cat"), ("SCENE", "lake"), ("SCENE", "mountain"), ("STYLE", "anime")]
        similarities = [0.20, 0.29, 0.10, 0.13]
        text_embeds = np.zeros((4, 4), dtype=np.float32)
        for row, value in enumerate(similarities):
            text_embeds[row][0] = value
        image_feature = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float32)
        scores: dict = {}
        with patch.object(
            app.model_manager,
            "acquire_lightweight_vision",
            return_value=(
                _FakeVisionSession(image_feature),
                labels,
                text_embeds,
                np.zeros((1, 1, 3), dtype=np.float32),
                np.ones((1, 1, 3), dtype=np.float32),
            ),
        ):
            app._run_lightweight_visual_inference(np.zeros((300, 300, 3), dtype=np.uint8), scores)

        self.assertIn(("SCENE", "lake"), scores)
        self.assertAlmostEqual(0.828, scores[("SCENE", "lake")][0], places=3)
        # SUBJECT 相似度未达 0.24 下限；SCENE 只报命名空间内的最大值；
        # STYLE 的相对最优仍是绝对低分，不得被 softmax 抬到可用区间。
        self.assertNotIn(("SUBJECT", "cat"), scores)
        self.assertNotIn(("SCENE", "mountain"), scores)
        self.assertLess(scores[("STYLE", "anime")][0], 0.40)

    def test_ram_plus_profile_is_downgraded_below_two_gigabytes(self):
        with patch.dict(os.environ, {"AI_VISION_PROFILE": "ram_plus_int8"}):
            with patch.object(app, "_read_cgroup_memory_limit", return_value=1024 * 1024 * 1024):
                self.assertEqual("lightweight", app._resolve_safe_vision_profile())

    def test_ram_plus_profile_stays_when_memory_allows(self):
        with patch.dict(os.environ, {"AI_VISION_PROFILE": "ram_plus_int8"}):
            with patch.object(app, "_read_cgroup_memory_limit", return_value=4 * 1024 * 1024 * 1024):
                self.assertEqual("ram_plus_int8", app._resolve_safe_vision_profile())

    def test_ready_reports_pipeline_version_without_internal_model_state(self):
        response = asyncio.run(app.ready())
        self.assertEqual("ok", response["status"])
        self.assertEqual(app.current_content_pipeline_version(), response["pipelineVersion"])
        self.assertEqual(app.OCR_PIPELINE_VERSION, response["ocrVersion"])
        self.assertNotIn("visionProfile", response)
        self.assertNotIn("visionModelState", response)


class SidecarTokenTest(unittest.TestCase):
    """验证推理接口认证、时间戳与签名绑定。"""

    def _request(self) -> SimpleNamespace:
        return SimpleNamespace(
            method="POST",
            url=SimpleNamespace(path="/analyze-content"),
        )

    def test_sidecar_auth_requires_token_timestamp_and_signature(self):
        with patch.object(app, "SIDECAR_SECRET", "expected-secret"):
            with self.assertRaises(HTTPException) as missing:
                app._require_sidecar_auth(self._request(), None)
            with self.assertRaises(HTTPException) as invalid_token:
                app._require_sidecar_auth(self._request(), "wrong-secret")
            timestamp = int(time.time())
            with self.assertRaises(HTTPException) as missing_signature:
                app._require_sidecar_auth(
                    self._request(), "expected-secret", str(timestamp), None
                )

        self.assertEqual(401, missing.exception.status_code)
        self.assertEqual(401, invalid_token.exception.status_code)
        self.assertEqual(401, missing_signature.exception.status_code)

    def test_sidecar_auth_accepts_valid_timestamp_and_signature(self):
        with patch.object(app, "SIDECAR_SECRET", "expected-secret"):
            timestamp = int(time.time())
            signature = app._sidecar_signature(timestamp, "POST", "/analyze-content")
            self.assertIsNone(app._require_sidecar_auth(
                self._request(), "expected-secret", str(timestamp), signature
            ))

    def test_sidecar_auth_rejects_stale_timestamp_and_tampered_path(self):
        with patch.object(app, "SIDECAR_SECRET", "expected-secret"):
            timestamp = int(time.time()) - app.SIDECAR_CLOCK_SKEW_SECONDS - 1
            signature = app._sidecar_signature(timestamp, "POST", "/analyze-content")
            with self.assertRaises(HTTPException) as stale:
                app._require_sidecar_auth(
                    self._request(), "expected-secret", str(timestamp), signature
                )
            fresh = int(time.time())
            wrong_signature = app._sidecar_signature(fresh, "POST", "/health")
            with self.assertRaises(HTTPException) as tampered:
                app._require_sidecar_auth(
                    self._request(), "expected-secret", str(fresh), wrong_signature
                )

        self.assertEqual(401, stale.exception.status_code)
        self.assertEqual(401, tampered.exception.status_code)

    def test_missing_secret_is_reported_as_unavailable(self):
        with patch.object(app, "SIDECAR_SECRET", ""):
            with self.assertRaises(HTTPException) as context:
                app._require_sidecar_auth(self._request(), "anything")
        self.assertEqual(503, context.exception.status_code)


if __name__ == "__main__":
    unittest.main()
