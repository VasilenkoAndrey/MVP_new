import React, { useState, useRef, useEffect, useCallback } from "react";
import { Canvas } from "@react-three/fiber";
import { OrbitControls, TransformControls, Line, Html } from "@react-three/drei";
import * as THREE from "three";
import { STLLoader } from "three/examples/jsm/loaders/STLLoader.js";
import { Box, Button, Typography, Paper, Stack, Alert } from "@mui/material";

export type PointType = "calibration1" | "calibration2" | "axis_start" | "axis_end" | 
                        "length_start" | "length_end" | "width_left" | "width_right";

export interface MeasurementPoint {
  id: string;
  type: PointType;
  position: [number, number, number];
  color: string;
  label: string;
}

interface ModelViewerProps {
  modelUrl?: string;
  onPointAdd: (point: MeasurementPoint) => void;
  onPointUpdate: (pointId: string, position: [number, number, number]) => void;
  onPointRemove: (pointId: string) => void;
  points: MeasurementPoint[];
  activePointType?: PointType | null;
  onActivePointTypeChange: (type: PointType | null) => void;
}

const ModelMesh: React.FC<{ 
  url: string; 
  onMeshClick: (point: THREE.Vector3) => void;
  wireframe: boolean;
}> = ({ url, onMeshClick, wireframe }) => {
  const [geometry, setGeometry] = useState<THREE.BufferGeometry | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string>("");

  useEffect(() => {
    if (!url) return;
    setLoading(true);
    setError("");
    
    const loader = new STLLoader();
    
    fetch(url)
      .then(response => {
        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
        return response.arrayBuffer();
      })
      .then(buffer => {
        try {
          const geom = loader.parse(buffer);
          geom.computeVertexNormals();
          geom.computeBoundingBox();
          const center = new THREE.Vector3();
          geom.boundingBox?.getCenter(center);
          geom.translate(-center.x, -center.y, -center.z);
          setGeometry(geom);
          setLoading(false);
        } catch (parseError) {
          console.error("Error parsing STL:", parseError);
          setError("Ошибка парсинга STL файла");
          setLoading(false);
        }
      })
      .catch(err => {
        console.error("Error loading STL:", err);
        setError(`Ошибка загрузки модели: ${err.message}`);
        setLoading(false);
      });
  }, [url]);

  if (loading) {
    return (
      <Html center>
        <Paper sx={{ p: 2 }}>
          <Typography variant="body2">Загрузка модели...</Typography>
        </Paper>
      </Html>
    );
  }

  if (error) {
    return (
      <Html center>
        <Paper sx={{ p: 2 }}>
          <Typography variant="body2" color="error">{error}</Typography>
        </Paper>
      </Html>
    );
  }

  if (!geometry) return null;

  return (
    <mesh
      geometry={geometry}
      onClick={(e) => {
        e.stopPropagation();
        if (e.point) onMeshClick(e.point.clone());
      }}
    >
      <meshStandardMaterial 
        color="#c0c0c0" 
        roughness={0.7}
        metalness={0.1}
        side={THREE.DoubleSide}
        wireframe={wireframe}
      />
    </mesh>
  );
};

const PointMarker: React.FC<{
  point: MeasurementPoint;
  isActive: boolean;
  onSelect: (point: MeasurementPoint) => void;
  onDrag: (pointId: string, position: [number, number, number]) => void;
}> = ({ point, isActive, onSelect, onDrag }) => {
  const meshRef = useRef<THREE.Mesh>(null);

  return (
    <group>
      <mesh
        ref={meshRef}
        position={point.position}
        onClick={(e) => {
          e.stopPropagation();
          onSelect(point);
        }}
      >
        <sphereGeometry args={[isActive ? 2.5 : 1.5, 32, 32]} />
        <meshStandardMaterial 
          color={isActive ? "#ff0000" : point.color}
          emissive={isActive ? "#ff0000" : "#000000"}
          emissiveIntensity={isActive ? 0.5 : 0}
        />
      </mesh>
      
      <Html position={[point.position[0], point.position[1] + 3, point.position[2]]}>
        <Box
          sx={{
            bgcolor: isActive ? "#ff0000" : point.color,
            color: "white",
            px: 1,
            py: 0.5,
            borderRadius: 1,
            fontSize: "10px",
            whiteSpace: "nowrap",
            pointerEvents: "none",
            userSelect: "none"
          }}
        >
          {point.label}
        </Box>
      </Html>
      
      {isActive && (
        <TransformControls
          object={meshRef}
          mode="translate"
          size={1.5}
          onObjectChange={() => {
            if (meshRef.current) {
              onDrag(
                point.id,
                [
                  meshRef.current.position.x,
                  meshRef.current.position.y,
                  meshRef.current.position.z
                ]
              );
            }
          }}
        />
      )}
    </group>
  );
};

const MeasurementLines: React.FC<{ points: MeasurementPoint[] }> = ({ points }) => {
  const lines: Array<{ points: [number, number, number][], color: string }> = [];
  
  const axisStart = points.find(p => p.type === "axis_start");
  const axisEnd = points.find(p => p.type === "axis_end");
  if (axisStart && axisEnd) {
    lines.push({ points: [axisStart.position, axisEnd.position], color: "#2196f3" });
  }
  
  const lengthStart = points.find(p => p.type === "length_start");
  const lengthEnd = points.find(p => p.type === "length_end");
  if (lengthStart && lengthEnd) {
    lines.push({ points: [lengthStart.position, lengthEnd.position], color: "#4caf50" });
  }
  
  const widthLeft = points.find(p => p.type === "width_left");
  const widthRight = points.find(p => p.type === "width_right");
  if (widthLeft && widthRight) {
    lines.push({ points: [widthLeft.position, widthRight.position], color: "#ff9800" });
  }
  
  const cal1 = points.find(p => p.type === "calibration1");
  const cal2 = points.find(p => p.type === "calibration2");
  if (cal1 && cal2) {
    lines.push({ points: [cal1.position, cal2.position], color: "#9c27b0" });
  }
  
  return (
    <>
      {lines.map((line, index) => (
        <Line
          key={index}
          points={line.points}
          color={line.color}
          lineWidth={2}
        />
      ))}
    </>
  );
};

const ModelViewer: React.FC<ModelViewerProps> = ({
  modelUrl,
  onPointAdd,
  onPointUpdate,
  onPointRemove,
  points,
  activePointType,
  onActivePointTypeChange
}) => {
  const [selectedPoint, setSelectedPoint] = useState<string | null>(null);
  const [wireframe, setWireframe] = useState(false);

  const handleMeshClick = useCallback((point: THREE.Vector3) => {
    if (!activePointType) return;
    
    const roundedPosition: [number, number, number] = [
      Math.round(point.x * 100) / 100,
      Math.round(point.y * 100) / 100,
      Math.round(point.z * 100) / 100
    ];
    
    const newPoint: MeasurementPoint = {
      id: `${activePointType}_${Date.now()}`,
      type: activePointType,
      position: roundedPosition,
      color: getPointColor(activePointType),
      label: getPointLabel(activePointType)
    };
    
    onPointAdd(newPoint);
    
    const nextType = getNextPointType(activePointType);
    onActivePointTypeChange(nextType);
  }, [activePointType, onPointAdd, onActivePointTypeChange]);

  return (
    <Box sx={{ position: "relative", height: "100%", minHeight: 400 }}>
      <Canvas
        camera={{ position: [0, 0, 200], fov: 50, near: 0.1, far: 2000 }}
        onPointerMissed={() => setSelectedPoint(null)}
        gl={{ preserveDrawingBuffer: true }}
      >
        <ambientLight intensity={0.6} />
        <directionalLight position={[100, 100, 100]} intensity={1} />
        <directionalLight position={[-100, -100, -100]} intensity={0.5} />
        <hemisphereLight intensity={0.3} />
        
        <gridHelper args={[400, 40, "#666666", "#444444"]} />
        <axesHelper args={[150]} />
        
        {modelUrl && (
          <ModelMesh 
            url={modelUrl} 
            onMeshClick={handleMeshClick}
            wireframe={wireframe}
          />
        )}
        
        {points.map((point) => (
          <PointMarker
            key={point.id}
            point={point}
            isActive={selectedPoint === point.id}
            onSelect={(p) => setSelectedPoint(p.id)}
            onDrag={onPointUpdate}
          />
        ))}
        
        <MeasurementLines points={points} />
        
        <OrbitControls
          enablePan={true}
          enableZoom={true}
          enableRotate={true}
          minDistance={20}
          maxDistance={500}
          makeDefault
        />
      </Canvas>
      
      <Paper
        sx={{
          position: "absolute",
          top: 16,
          right: 16,
          p: 2,
          maxWidth: 200,
          zIndex: 10,
          bgcolor: "rgba(255, 255, 255, 0.9)"
        }}
      >
        <Typography variant="subtitle2" gutterBottom>
          Управление
        </Typography>
        
        <Stack spacing={1}>
          <Button
            size="small"
            variant={wireframe ? "contained" : "outlined"}
            onClick={() => setWireframe(!wireframe)}
          >
            {wireframe ? "Каркас: Вкл" : "Каркас: Выкл"}
          </Button>
          
          {activePointType && (
            <Alert severity="info" sx={{ mt: 1 }}>
              Кликните на модель для установки: {getPointLabel(activePointType)}
            </Alert>
          )}
        </Stack>
      </Paper>
      
      {selectedPoint && (
        <Paper
          sx={{
            position: "absolute",
            bottom: 16,
            left: 16,
            p: 1,
            zIndex: 10,
            bgcolor: "rgba(255, 255, 255, 0.9)"
          }}
        >
          <Typography variant="caption" display="block">
            {points.find(p => p.id === selectedPoint)?.label}
          </Typography>
          <Button
            size="small"
            color="error"
            onClick={() => {
              onPointRemove(selectedPoint);
              setSelectedPoint(null);
            }}
          >
            Удалить
          </Button>
        </Paper>
      )}
    </Box>
  );
};

function getPointColor(type: PointType): string {
  const colors: Record<PointType, string> = {
    "calibration1": "#9c27b0",
    "calibration2": "#9c27b0",
    "axis_start": "#2196f3",
    "axis_end": "#2196f3",
    "length_start": "#4caf50",
    "length_end": "#4caf50",
    "width_left": "#ff9800",
    "width_right": "#ff9800"
  };
  return colors[type];
}

function getPointLabel(type: PointType): string {
  const labels: Record<PointType, string> = {
    "calibration1": "Калибровка 1",
    "calibration2": "Калибровка 2",
    "axis_start": "Начало оси",
    "axis_end": "Конец оси",
    "length_start": "Начало длины",
    "length_end": "Конец длины",
    "width_left": "Левая ширина",
    "width_right": "Правая ширина"
  };
  return labels[type];
}

function getNextPointType(type: PointType): PointType | null {
  const sequence: Record<PointType, PointType | null> = {
    "calibration1": "calibration2",
    "calibration2": "axis_start",
    "axis_start": "axis_end",
    "axis_end": "length_start",
    "length_start": "length_end",
    "length_end": "width_left",
    "width_left": "width_right",
    "width_right": null
  };
  return sequence[type];
}

export default ModelViewer;
export { getPointLabel, getPointColor };

