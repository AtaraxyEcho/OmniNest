"""
OmniNest 图像识别侧车服务。
提供人脸检测、人脸嵌入和人脸聚类功能。
"""

import hmac
import io
import logging
import os
from asyncio import Semaphore, to_thread
from contextlib import asynccontextmanager
from typing import Annotated

import numpy as np
from fastapi import Depends, FastAPI, File, Header, HTTPException, UploadFile
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 全局模型引用（延迟加载）。InsightFace 使用 ONNX Runtime，不需要 PyTorch。
face_app = None
REQUIRED_FACE_MODULES = ("detection", "recognition")
SIDECAR_TOKEN_HEADER = "X-OmniNest-Sidecar-Token"
SIDECAR_SECRET = os.environ.get("OMNINEST_AI_SIDECAR_SECRET", "")
# 与后端 photo.ai.max-image-bytes 默认值（67108864）对齐；后端按同一上限做前置拒绝。
MAX_IMAGE_BYTES = int(os.environ.get("AI_MAX_IMAGE_BYTES", str(64 * 1024 * 1024)))
MAX_IMAGE_WIDTH = int(os.environ.get("AI_MAX_IMAGE_WIDTH", "30000"))
MAX_IMAGE_HEIGHT = int(os.environ.get("AI_MAX_IMAGE_HEIGHT", "30000"))
MAX_IMAGE_PIXELS = int(os.environ.get("AI_MAX_IMAGE_PIXELS", "100000000"))
MAX_CLUSTER_FACES = int(os.environ.get("AI_MAX_CLUSTER_FACES", "10000"))
FACE_EMBEDDING_DIMENSION = int(os.environ.get("AI_FACE_EMBEDDING_DIMENSION", "512"))
MAX_CONCURRENT_INFERENCES = int(os.environ.get("AI_MAX_CONCURRENT_INFERENCES", "2"))
CONTENT_ANALYSIS_SCHEMA_VERSION = 2
CONTENT_ANALYSIS_PIPELINE_VERSION = os.environ.get(
    "IMAGE_ANALYSIS_PIPELINE_VERSION",
    "face-recognition-v1",
)
UPLOAD_READ_CHUNK_SIZE = 1024 * 1024
inference_slots = Semaphore(MAX_CONCURRENT_INFERENCES)


def _has_required_face_models(candidate) -> bool:
    """检查 InsightFace 是否同时加载了检测和识别模型。"""
    if candidate is None:
        return False
    models = getattr(candidate, "models", None)
    return models is not None and all(module in models for module in REQUIRED_FACE_MODULES)


def _face_recognition_ready() -> bool:
    """返回人脸检测与识别能力是否完整可用。"""
    return _has_required_face_models(face_app)


def _require_sidecar_token(
    token: Annotated[str | None, Header(alias=SIDECAR_TOKEN_HEADER)] = None,
) -> None:
    """只接受后端持有的侧车共享密钥。"""
    if not SIDECAR_SECRET:
        raise HTTPException(status_code=503, detail="AI sidecar authentication is not configured")
    if token is None or not hmac.compare_digest(token, SIDECAR_SECRET):
        raise HTTPException(status_code=401, detail="Unauthorized")


def _verify_image_bounds(chunks: bytes) -> None:
    """同步执行图片解码与边界校验，调用方需放入线程以避免阻塞事件循环。"""
    from PIL import Image

    with Image.open(io.BytesIO(chunks)) as decoded:
        width, height = decoded.size
        if (
            width <= 0
            or height <= 0
            or width > MAX_IMAGE_WIDTH
            or height > MAX_IMAGE_HEIGHT
            or width * height > MAX_IMAGE_PIXELS
        ):
            raise HTTPException(status_code=413, detail="Image dimensions exceed limit")
        decoded.verify()


async def _read_bounded_image(image: UploadFile) -> bytes:
    """分块读取上传图片，并同时限制编码尺寸与解码像素。"""
    content_length = image.headers.get("content-length")
    if content_length is not None:
        try:
            if int(content_length) > MAX_IMAGE_BYTES:
                raise HTTPException(status_code=413, detail="Image exceeds size limit")
        except ValueError as exception:
            raise HTTPException(status_code=400, detail="Invalid content length") from exception

    chunks = bytearray()
    while True:
        chunk = await image.read(UPLOAD_READ_CHUNK_SIZE)
        if not chunk:
            break
        if len(chunks) + len(chunk) > MAX_IMAGE_BYTES:
            raise HTTPException(status_code=413, detail="Image exceeds size limit")
        chunks.extend(chunk)
    if not chunks:
        raise HTTPException(status_code=400, detail="Image is empty")

    try:
        await to_thread(_verify_image_bounds, bytes(chunks))
    except HTTPException:
        raise
    except Exception as exception:
        raise HTTPException(status_code=400, detail="Unable to decode image") from exception
    return bytes(chunks)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期管理：启动时加载模型，关闭时释放资源。"""
    global face_app
    logger.info("正在加载人脸识别模型...")

    # 人脸检测只加载检测和识别模块，避免占用无关模型内存。
    try:
        from insightface.app import FaceAnalysis

        insightface_root = os.environ.get(
            "INSIGHTFACE_ROOT",
            "/app/models/insightface",
        )
        loaded_face_app = FaceAnalysis(
            name="buffalo_l",
            root=insightface_root,
            allowed_modules=["detection", "recognition"],
            providers=["CPUExecutionProvider"],
        )
        loaded_face_app.prepare(ctx_id=-1, det_size=(640, 640))
        if not _has_required_face_models(loaded_face_app):
            raise RuntimeError("InsightFace detection/recognition models are incomplete")
        face_app = loaded_face_app
        logger.info("InsightFace 人脸检测模型加载完成")
    except Exception as exception:
        face_app = None
        logger.warning("InsightFace 加载失败，人脸检测功能不可用: %s", exception)

    yield

    # 清理资源
    face_app = None
    logger.info("人脸识别模型已释放")


app = FastAPI(
    title="OmniNest Image Recognition Sidecar",
    description="照片图像识别服务：人脸检测、人脸嵌入和人脸聚类",
    version="2.0.0",
    lifespan=lifespan,
)


# ─── 数据模型 ───


class FaceDetection(BaseModel):
    bbox_x: int
    bbox_y: int
    bbox_w: int
    bbox_h: int
    embedding: list[float]


class SceneLabel(BaseModel):
    name: str
    confidence: float


class SceneClassification(BaseModel):
    labels: list[SceneLabel]


class BoundingBox(BaseModel):
    x: float
    y: float
    width: float
    height: float


class ContentObservation(BaseModel):
    namespace: str
    code: str
    confidence: float
    source: str
    boxes: list[BoundingBox] = Field(default_factory=list)


class ContentAnalysis(BaseModel):
    schema_version: int = Field(alias="schemaVersion")
    pipeline_version: str = Field(alias="pipelineVersion")
    observations: list[ContentObservation]

    model_config = {"populate_by_name": True}


class ClusterRequest(BaseModel):
    embeddings: list[list[float]] = Field(max_length=MAX_CLUSTER_FACES)


def _analyze_content_sync(contents: bytes) -> ContentAnalysis:
    """保留旧结构化接口，但不再加载场景或主体分类模型。"""
    return ContentAnalysis(
        schemaVersion=CONTENT_ANALYSIS_SCHEMA_VERSION,
        pipelineVersion=CONTENT_ANALYSIS_PIPELINE_VERSION,
        observations=[],
    )


def _legacy_scene_labels(content: ContentAnalysis) -> list[SceneLabel]:
    """将结构化结果转换为旧场景接口，不返回主体检测结果。"""
    labels = [
        SceneLabel(name=observation.code, confidence=observation.confidence)
        for observation in content.observations
        if observation.namespace == "SCENE"
    ]
    labels.sort(key=lambda label: label.confidence, reverse=True)
    return labels


# ─── 人脸检测 ───


@app.post(
    "/detect-faces",
    response_model=list[FaceDetection],
    dependencies=[Depends(_require_sidecar_token)],
)
async def detect_faces(image: UploadFile = File(...)):
    """检测图片中的人脸，返回位置和 512 维嵌入向量。"""
    if not _face_recognition_ready():
        raise HTTPException(status_code=503, detail="人脸检测模型未加载")

    try:
        import cv2

        contents = await _read_bounded_image(image)
        nparr = np.frombuffer(contents, np.uint8)
        async with inference_slots:
            img = await to_thread(cv2.imdecode, nparr, cv2.IMREAD_COLOR)

            if img is None:
                raise HTTPException(status_code=400, detail="Unable to decode image")

            faces = await to_thread(face_app.get, img)
        results = []

        for face in faces:
            bbox = face.bbox.astype(int)
            results.append(
                FaceDetection(
                    bbox_x=int(bbox[0]),
                    bbox_y=int(bbox[1]),
                    bbox_w=int(bbox[2] - bbox[0]),
                    bbox_h=int(bbox[3] - bbox[1]),
                    embedding=face.embedding.tolist(),
                )
            )

        logger.info("检测到 %s 张人脸", len(results))
        return results

    except HTTPException:
        raise
    except Exception:
        logger.exception("人脸检测失败")
        raise HTTPException(status_code=500, detail="Face detection failed") from None


# ─── 兼容内容接口 ───


@app.post(
    "/analyze-content",
    response_model=ContentAnalysis,
    dependencies=[Depends(_require_sidecar_token)],
)
async def analyze_content(image: UploadFile = File(...)):
    """保留后端契约，当前仅返回空观察项和人脸识别流水线版本。"""
    if not _face_recognition_ready():
        raise HTTPException(status_code=503, detail="人脸识别模型未加载")

    try:
        contents = await _read_bounded_image(image)
        async with inference_slots:
            result = await to_thread(_analyze_content_sync, contents)
        logger.info(
            "图像分析完成: observationCount=%s, pipelineVersion=%s",
            len(result.observations),
            result.pipeline_version,
        )
        return result
    except HTTPException:
        raise
    except Exception:
        logger.exception("图像分析失败")
        raise HTTPException(status_code=500, detail="Image analysis failed") from None


# ─── 兼容接口 ───


@app.post(
    "/classify-scene",
    response_model=SceneClassification,
    dependencies=[Depends(_require_sidecar_token)],
)
async def classify_scene(image: UploadFile = File(...)):
    """兼容旧客户端；精简镜像不提供场景模型，因此返回空标签。"""
    try:
        await _read_bounded_image(image)
        logger.info("场景分类接口以兼容模式返回空标签")
        return SceneClassification(labels=[])

    except HTTPException:
        raise
    except Exception:
        logger.exception("兼容场景分类失败")
        raise HTTPException(status_code=500, detail="Scene classification failed") from None


# ─── 人脸聚类 ───


@app.post(
    "/cluster-faces",
    response_model=list[int],
    dependencies=[Depends(_require_sidecar_token)],
)
async def cluster_faces(request: ClusterRequest):
    """对人脸嵌入向量进行聚类，返回每个向量的聚类 ID。"""
    try:
        from sklearn.cluster import DBSCAN
        from sklearn.preprocessing import normalize

        if any(len(embedding) != FACE_EMBEDDING_DIMENSION for embedding in request.embeddings):
            raise HTTPException(status_code=422, detail="Invalid face embedding dimension")

        embeddings = np.asarray(request.embeddings, dtype=np.float32)
        if not np.isfinite(embeddings).all():
            raise HTTPException(status_code=422, detail="Face embeddings must be finite")
        if len(embeddings) == 0:
            return []

        if len(embeddings) == 1:
            return [0]

        # L2 归一化（InsightFace 输出已归一化，但确保安全）
        embeddings = normalize(embeddings)

        # DBSCAN 聚类
        # eps=0.6 是人脸聚类的经验值，余弦距离阈值
        async with inference_slots:
            clusterer = DBSCAN(eps=0.6, min_samples=2, metric="cosine")
            clustering = await to_thread(clusterer.fit, embeddings)

        # 将 -1（噪声点）转为独立聚类 ID
        labels = clustering.labels_
        max_label = labels.max()
        result = []
        for label in labels:
            if label == -1:
                max_label += 1
                result.append(int(max_label))
            else:
                result.append(int(label))

        n_clusters = len(set(result))
        logger.info("人脸聚类完成: %s 个向量 -> %s 个聚类", len(embeddings), n_clusters)
        return result

    except HTTPException:
        raise
    except Exception:
        logger.exception("人脸聚类失败")
        raise HTTPException(status_code=500, detail="Face clustering failed") from None


# ─── 健康检查 ───


@app.get("/health")
async def health():
    """健康检查端点。"""
    recognition_ready = _face_recognition_ready()
    return {
        "status": "ok",
        "image_recognition": recognition_ready,
        "face_detection": recognition_ready,
        "content_analysis": False,
        "face_clustering": True,
    }


@app.get("/ready")
async def ready():
    """就绪检查端点，仅要求人脸识别模型加载完成。"""
    recognition_ready = _face_recognition_ready()
    readiness = {
        "image_recognition": recognition_ready,
        "face_detection": recognition_ready,
        "content_analysis": False,
        "face_clustering": True,
    }
    if not recognition_ready:
        raise HTTPException(status_code=503, detail=readiness)
    return {"status": "ready", **readiness}
