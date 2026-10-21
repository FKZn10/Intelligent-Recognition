import torch
import torch.nn as nn
from torchvision import models, transforms
from PIL import Image
from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import io
import logging
from datetime import datetime

# --- 全局配置 ---
APP_CONFIG = {
    "DEVICE": torch.device("cuda" if torch.cuda.is_available() else "cpu"),
    "STATE_MODEL": "cnn_state.pth",
    "RANK_MODEL": "cnn_level.pth",
    "UPLOAD_DIR": "archive_samples",
    "PORT": 5001  # 故意换一个端口避免冲突
}

# 日志配置
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

if not os.path.exists(APP_CONFIG["UPLOAD_DIR"]):
    os.makedirs(APP_CONFIG["UPLOAD_DIR"])


# --- 模型定义 ---
class EfficientExtractor(nn.Module):
    """基于 EfficientNetV2-S 的特征提取器"""

    def __init__(self, out_features):
        super().__init__()
        # 使用预训练架构作为骨干
        self.model = models.efficientnet_v2_s(weights=None)
        # 修改分类头
        self.model.classifier = nn.Sequential(
            nn.Dropout(p=0.3, inplace=True),
            nn.Linear(self.model.classifier[1].in_features, out_features),
        )

    def forward(self, x):
        return self.model(x)


class VisionSystem:
    """视觉推理引擎封装"""

    def __init__(self):
        self.transform = transforms.Compose([
            transforms.Resize((288, 288)),
            transforms.ToTensor(),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
        ])

        # 初始化双模型
        self.state_net = self._load_engine(APP_CONFIG["STATE_MODEL"], 4)
        self.rank_net = self._load_engine(APP_CONFIG["RANK_MODEL"], 5)

        self.state_labels = {0: "损毁", 1: "合格", 2: "污染", 3: "褶皱"}
        self.rank_labels = {i: f"等级_{i + 1}" for i in range(5)}

    def _load_engine(self, path, num_classes):
        model = EfficientExtractor(num_classes).to(APP_CONFIG["DEVICE"])
        if os.path.exists(path):
            try:
                ckpt = torch.load(path, map_location=APP_CONFIG["DEVICE"])
                # 兼容性处理：自动处理 state_dict 的 key
                clean_ckpt = {k.replace('backbone.', '').replace('model.', ''): v for k, v in ckpt.items()}
                # 重新映射到我们的模型结构
                model.model.load_state_dict(clean_ckpt, strict=False)
                logger.info(f"Successfully loaded: {path}")
            except Exception as e:
                logger.error(f"Error loading {path}: {e}")
        return model.eval()

    def run_inference(self, img_bytes):
        img = Image.open(io.BytesIO(img_bytes)).convert('RGB')
        tensor = self.transform(img).unsqueeze(0).to(APP_CONFIG["DEVICE"])

        with torch.no_grad():
            # 并行执行（逻辑上）
            raw_state = self.state_net(tensor)
            raw_rank = self.rank_net(tensor)

            # 计算概率
            prob_state = torch.softmax(raw_state, dim=1)
            prob_rank = torch.softmax(raw_rank, dim=1)

            val_s, idx_s = torch.max(prob_state, 1)
            val_r, idx_r = torch.max(prob_rank, 1)

        return {
            "state": self.state_labels.get(idx_s.item()),
            "state_conf": float(val_s),
            "rank": self.rank_labels.get(idx_r.item()),
            "rank_conf": float(val_r)
        }


# 初始化系统单例
engine = VisionSystem()


# --- 路由定义 ---
@app.route('/v1/vision/analyze', methods=['POST'])
def analyze_v1():
    if 'image' not in request.files:
        return jsonify({"status": "error", "message": "Missing image field"}), 400

    file = request.files['image']
    try:
        content = file.read()

        # 异步持久化（保存样张）
        timestamp = datetime.now().strftime("%f")
        filename = f"sample_{timestamp}_{file.filename}"
        with open(os.path.join(APP_CONFIG["UPLOAD_DIR"], filename), "wb") as f:
            f.write(content)

        # 执行核心算法
        results = engine.run_inference(content)

        return jsonify({
            "status": "success",
            "timestamp": datetime.now().isoformat(),
            "payload": {
                "classification": results["state"],
                "quality_score": results["rank"],
                "metrics": {
                    "cls_acc": f"{results['state_conf']:.4f}",
                    "rank_acc": f"{results['rank_conf']:.4f}"
                }
            }
        })

    except Exception as e:
        logger.exception("Inference Failure")
        return jsonify({"status": "fail", "reason": str(e)}), 500


if __name__ == '__main__':
    logger.info(f"=== Vision Analysis System Server Booting ===")
    logger.info(f"Target Device: {APP_CONFIG['DEVICE']}")
    app.run(host='0.0.0.0', port=APP_CONFIG["PORT"])