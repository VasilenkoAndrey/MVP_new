from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
import uuid
from datetime import datetime
import os
import json
import numpy as np
import math
import logging
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Trophy Measurement API",
    description="API для цифрового измерения охотничьих трофеев по Методу №6",
    version="0.2.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

TROPHIES = {}
MEASUREMENTS = {}
UPLOAD_DIR = Path("uploads")
UPLOAD_DIR.mkdir(exist_ok=True)

MAX_FILE_SIZE = 500 * 1024 * 1024

class Point3D(BaseModel):
    x: float
    y: float
    z: float

class TrophyCreate(BaseModel):
    animal_species: str
    hunt_date: str
    hunt_location: str
    owner_name: str
    additional_data: Optional[Dict[str, Any]] = {}

class CalibrationData(BaseModel):
    point1: Point3D
    point2: Point3D
    actual_distance_mm: float

class AxisData(BaseModel):
    axis_start: Point3D
    axis_end: Point3D

class MeasurementRequest(BaseModel):
    calibration: CalibrationData
    axis: AxisData
    length_start: Point3D
    length_end: Point3D
    width_left: Point3D
    width_right: Point3D

class MeasurementService:
    ALGORITHM_VERSION = "1.0"
    WIDTH_TOLERANCE_DEGREES = 5.0
    
    @staticmethod
    def calculate_scale_factor(point1: Point3D, point2: Point3D, actual_distance_mm: float) -> float:
        p1 = np.array([point1.x, point1.y, point1.z])
        p2 = np.array([point2.x, point2.y, point2.z])
        model_distance = np.linalg.norm(p2 - p1)
        if model_distance == 0:
            raise ValueError("Точки калибровки совпадают")
        return float(actual_distance_mm / model_distance)
    
    @staticmethod
    def calculate_measurements(
        axis_start: Point3D, axis_end: Point3D,
        length_start: Point3D, length_end: Point3D,
        width_left: Point3D, width_right: Point3D,
        scale_factor: float
    ) -> Dict[str, Any]:
        axis_start_np = np.array([axis_start.x, axis_start.y, axis_start.z])
        axis_end_np = np.array([axis_end.x, axis_end.y, axis_end.z])
        length_start_np = np.array([length_start.x, length_start.y, length_start.z])
        length_end_np = np.array([length_end.x, length_end.y, length_end.z])
        width_left_np = np.array([width_left.x, width_left.y, width_left.z])
        width_right_np = np.array([width_right.x, width_right.y, width_right.z])
        
        axis_vector = axis_end_np - axis_start_np
        axis_length = np.linalg.norm(axis_vector)
        if axis_length == 0:
            raise ValueError("Точки оси совпадают")
        axis_direction = axis_vector / axis_length
        
        length_start_proj = np.dot(length_start_np - axis_start_np, axis_direction)
        length_end_proj = np.dot(length_end_np - axis_start_np, axis_direction)
        raw_length = abs(length_end_proj - length_start_proj)
        
        width_vector = width_right_np - width_left_np
        raw_width = np.linalg.norm(width_vector)
        
        width_angle_degrees = 0.0
        if raw_width > 0:
            width_direction = width_vector / raw_width
            angle_cos = np.dot(width_direction, axis_direction)
            angle_rad = math.acos(np.clip(angle_cos, -1.0, 1.0))
            width_angle_degrees = math.degrees(angle_rad)
        
        perpendicular_deviation = abs(90.0 - width_angle_degrees)
        
        final_length_mm = raw_length * scale_factor
        final_width_mm = raw_width * scale_factor
        final_total_mm = final_length_mm + final_width_mm
        
        return {
            "raw_length_mm": float(raw_length),
            "raw_width_mm": float(raw_width),
            "final_length_mm": float(final_length_mm),
            "final_width_mm": float(final_width_mm),
            "final_total_mm": float(final_total_mm),
            "final_length_cm": float(final_length_mm / 10),
            "final_width_cm": float(final_width_mm / 10),
            "final_total_cm": float(final_total_mm / 10),
            "width_angle_degrees": float(width_angle_degrees),
            "perpendicular_deviation_degrees": float(perpendicular_deviation),
            "is_width_perpendicular": perpendicular_deviation <= MeasurementService.WIDTH_TOLERANCE_DEGREES,
            "axis_direction": {
                "x": float(axis_direction[0]),
                "y": float(axis_direction[1]),
                "z": float(axis_direction[2])
            }
        }

def parse_stl_info(file_path: Path) -> Dict[str, Any]:
    info = {
        "format": "unknown",
        "vertices_count": 0,
        "triangles_count": 0,
        "bounding_box": None,
        "file_size": file_path.stat().st_size
    }
    
    try:
        with open(file_path, "rb") as f:
            header = f.read(80)
            f.seek(0)
            
            try:
                f.seek(80)
                triangle_count_bytes = f.read(4)
                if len(triangle_count_bytes) == 4:
                    triangle_count = int.from_bytes(triangle_count_bytes, "little")
                    expected_size = 84 + triangle_count * 50
                    
                    if file_path.stat().st_size == expected_size:
                        info["format"] = "binary"
                        info["triangles_count"] = triangle_count
                        info["vertices_count"] = triangle_count * 3
                        
                        f.seek(84)
                        vertices = []
                        for _ in range(triangle_count):
                            f.read(12)
                            for _ in range(3):
                                vertex = np.frombuffer(f.read(12), dtype=np.float32)
                                vertices.append(vertex)
                            f.read(2)
                        
                        if vertices:
                            vertices_array = np.array(vertices)
                            info["bounding_box"] = {
                                "min": {"x": float(vertices_array[:, 0].min()), 
                                       "y": float(vertices_array[:, 1].min()), 
                                       "z": float(vertices_array[:, 2].min())},
                                "max": {"x": float(vertices_array[:, 0].max()), 
                                       "y": float(vertices_array[:, 1].max()), 
                                       "z": float(vertices_array[:, 2].max())}
                            }
            except:
                pass
            
            if info["format"] == "unknown":
                f.seek(0)
                content = f.read(1000).decode("ascii", errors="ignore")
                if "solid" in content.lower():
                    info["format"] = "ascii"
                    f.seek(0)
                    full_content = f.read().decode("ascii", errors="ignore")
                    triangle_count = full_content.lower().count("facet normal")
                    info["triangles_count"] = triangle_count
                    info["vertices_count"] = triangle_count * 3
    
    except Exception as e:
        logger.error(f"Ошибка парсинга STL: {str(e)}")
    
    return info

@app.get("/")
async def root():
    return {
        "service": "Trophy Measurement API",
        "version": "0.2.0",
        "method": "Метод №6 - Измерение черепов плотоядных",
        "status": "running"
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "trophies_count": len(TROPHIES),
        "measurements_count": len(MEASUREMENTS)
    }

@app.post("/api/trophies")
async def create_trophy(trophy: TrophyCreate):
    trophy_id = str(uuid.uuid4())
    trophy_data = {
        "id": trophy_id,
        "animal_species": trophy.animal_species,
        "hunt_date": trophy.hunt_date,
        "hunt_location": trophy.hunt_location,
        "owner_name": trophy.owner_name,
        "status": "DRAFT",
        "additional_data": trophy.additional_data,
        "models": [],
        "created_at": datetime.now().isoformat()
    }
    TROPHIES[trophy_id] = trophy_data
    logger.info(f"Создан трофей: {trophy_id} ({trophy.animal_species})")
    return trophy_data

@app.get("/api/trophies")
async def list_trophies():
    return list(TROPHIES.values())

@app.get("/api/trophies/{trophy_id}")
async def get_trophy(trophy_id: str):
    if trophy_id not in TROPHIES:
        raise HTTPException(404, "Трофей не найден")
    return TROPHIES[trophy_id]

@app.post("/api/trophies/{trophy_id}/upload-model")
async def upload_model(trophy_id: str, file: UploadFile = File(...)):
    if trophy_id not in TROPHIES:
        raise HTTPException(404, "Трофей не найден")
    
    if not file.filename.lower().endswith(".stl"):
        raise HTTPException(400, "Поддерживается только формат STL")
    
    content = await file.read()
    
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(400, f"Файл слишком большой. Максимальный размер: {MAX_FILE_SIZE // (1024*1024)} MB")
    
    trophy_dir = UPLOAD_DIR / trophy_id
    trophy_dir.mkdir(exist_ok=True)
    
    file_path = trophy_dir / file.filename
    with open(file_path, "wb") as f:
        f.write(content)
    
    stl_info = parse_stl_info(file_path)
    
    model_id = str(uuid.uuid4())
    model_info = {
        "id": model_id,
        "filename": file.filename,
        "file_path": str(file_path),
        "file_size": len(content),
        "format": stl_info["format"],
        "vertices_count": stl_info["vertices_count"],
        "triangles_count": stl_info["triangles_count"],
        "bounding_box": stl_info["bounding_box"],
        "uploaded_at": datetime.now().isoformat(),
        "status": "uploaded"
    }
    
    TROPHIES[trophy_id]["models"].append(model_info)
    TROPHIES[trophy_id]["status"] = "MODEL_UPLOADED"
    
    logger.info(f"Модель загружена для трофея {trophy_id}: {file.filename}")
    return model_info

@app.get("/api/trophies/{trophy_id}/models")
async def list_models(trophy_id: str):
    if trophy_id not in TROPHIES:
        raise HTTPException(404, "Трофей не найден")
    return TROPHIES[trophy_id]["models"]

@app.get("/api/models/{trophy_id}/{filename}")
async def download_model(trophy_id: str, filename: str):
    file_path = UPLOAD_DIR / trophy_id / filename
    if not file_path.exists():
        raise HTTPException(404, "Файл не найден")
    return FileResponse(
        path=str(file_path),
        filename=filename,
        media_type="application/sla"
    )

@app.delete("/api/models/{trophy_id}/{filename}")
async def delete_model(trophy_id: str, filename: str):
    if trophy_id not in TROPHIES:
        raise HTTPException(404, "Трофей не найден")
    
    file_path = UPLOAD_DIR / trophy_id / filename
    if file_path.exists():
        file_path.unlink()
        TROPHIES[trophy_id]["models"] = [
            m for m in TROPHIES[trophy_id]["models"] 
            if m["filename"] != filename
        ]
        if not TROPHIES[trophy_id]["models"]:
            TROPHIES[trophy_id]["status"] = "DRAFT"
        return {"status": "deleted", "filename": filename}
    
    raise HTTPException(404, "Файл не найден")

@app.post("/api/measurements/calculate")
async def calculate_measurement(data: MeasurementRequest):
    try:
        service = MeasurementService()
        scale_factor = service.calculate_scale_factor(
            data.calibration.point1,
            data.calibration.point2,
            data.calibration.actual_distance_mm
        )
        result = service.calculate_measurements(
            data.axis.axis_start,
            data.axis.axis_end,
            data.length_start,
            data.length_end,
            data.width_left,
            data.width_right,
            scale_factor
        )
        measurement_id = str(uuid.uuid4())
        result["measurement_id"] = measurement_id
        result["scale_factor"] = scale_factor
        result["algorithm_version"] = service.ALGORITHM_VERSION
        result["timestamp"] = datetime.now().isoformat()
        MEASUREMENTS[measurement_id] = result
        logger.info(f"Выполнено измерение: {measurement_id}")
        return result
    except ValueError as e:
        raise HTTPException(400, str(e))
    except Exception as e:
        logger.error(f"Ошибка расчета: {str(e)}")
        raise HTTPException(500, f"Ошибка расчета: {str(e)}")

@app.get("/api/measurements")
async def list_measurements():
    return list(MEASUREMENTS.values())

@app.get("/api/measurements/{measurement_id}")
async def get_measurement(measurement_id: str):
    if measurement_id not in MEASUREMENTS:
        raise HTTPException(404, "Измерение не найдено")
    return MEASUREMENTS[measurement_id]

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

