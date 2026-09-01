#!/bin/bash
# fix_app.sh - Исправление App.tsx для работы с IP 93.77.162.57

# Создаем правильный App.tsx
cat > frontend/src/App.tsx << 'EOF'
import React, { useState, useEffect, useRef, useCallback } from "react";
import {
  Container, Typography, Button, TextField, Card, CardContent,
  Grid, AppBar, Toolbar, Box, Alert, List, ListItem, ListItemText,
  Divider, Paper, Chip, IconButton, LinearProgress, Stack, Tabs, Tab
} from "@mui/material";
import DeleteIcon from "@mui/icons-material/Delete";
import CloudUploadIcon from "@mui/icons-material/CloudUpload";
import ThreeDRotationIcon from "@mui/icons-material/ThreeDRotation";
import StraightenIcon from "@mui/icons-material/Straighten";
import axios from "axios";
import ModelViewer, { MeasurementPoint, PointType } from "./components/ModelViewer";

// Используем IP-адрес сервера
const API_URL = "http://93.77.162.57:8000";

// Или можно автоматически определить хост
// const API_URL = window.location.protocol + "//" + window.location.hostname + ":8000";

interface Trophy {
  id: string;
  animal_species: string;
  hunt_date: string;
  hunt_location: string;
  owner_name: string;
  status: string;
  models: ModelInfo[];
}

interface ModelInfo {
  id: string;
  filename: string;
  file_size: number;
  format: string;
  vertices_count: number;
  triangles_count: number;
  bounding_box: any;
  uploaded_at: string;
  status: string;
}

interface MeasurementResult {
  measurement_id: string;
  final_length_cm: number;
  final_width_cm: number;
  final_total_cm: number;
  width_angle_degrees: number;
  perpendicular_deviation_degrees: number;
  is_width_perpendicular: boolean;
  scale_factor: number;
}

function App() {
  const [trophies, setTrophies] = useState<Trophy[]>([]);
  const [selectedTrophy, setSelectedTrophy] = useState<Trophy | null>(null);
  const [measurementResult, setMeasurementResult] = useState<MeasurementResult | null>(null);
  const [error, setError] = useState<string>("");
  const [success, setSuccess] = useState<string>("");
  const [uploading, setUploading] = useState<boolean>(false);
  const [uploadProgress, setUploadProgress] = useState<number>(0);
  const [activeTab, setActiveTab] = useState(0);
  const fileInputRef = useRef<HTMLInputElement>(null);
  
  const [measurementPoints, setMeasurementPoints] = useState<MeasurementPoint[]>([]);
  const [activePointType, setActivePointType] = useState<PointType | null>(null);
  const [currentModelUrl, setCurrentModelUrl] = useState<string>("");
  
  const [animalSpecies, setAnimalSpecies] = useState<string>("");
  const [huntDate, setHuntDate] = useState<string>("");
  const [huntLocation, setHuntLocation] = useState<string>("");
  const [ownerName, setOwnerName] = useState<string>("");
  const [calibrationDistance, setCalibrationDistance] = useState<number>(100);
  
  useEffect(() => {
    console.log("API URL:", API_URL);
    loadTrophies();
  }, []);
  
  const loadTrophies = async () => {
    try {
      const response = await axios.get(`${API_URL}/api/trophies`);
      setTrophies(response.data);
    } catch (error) {
      console.error("Ошибка загрузки трофеев:", error);
      if (axios.isAxiosError(error)) {
        if (error.code === "ERR_NETWORK") {
          setError(`Не удается подключиться к серверу ${API_URL}. Проверьте, что backend запущен.`);
        } else if (error.response?.status === 404) {
          setError("API endpoint не найден");
        }
      }
    }
  };
  
  const createTrophy = async () => {
    try {
      setError("");
      setSuccess("");
      
      if (!animalSpecies || !huntDate || !huntLocation || !ownerName) {
        setError("Заполните все поля");
        return;
      }
      
      const response = await axios.post(`${API_URL}/api/trophies`, {
        animal_species: animalSpecies,
        hunt_date: huntDate,
        hunt_location: huntLocation,
        owner_name: ownerName
      });
      
      setSuccess(`Трофей создан: ${response.data.animal_species}`);
      setAnimalSpecies("");
      setHuntDate("");
      setHuntLocation("");
      setOwnerName("");
      loadTrophies();
    } catch (error) {
      setError("Ошибка при создании трофея");
      console.error(error);
    }
  };
  
  const handleFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    
    if (!file) return;
    
    if (!selectedTrophy) {
      setError("Сначала выберите трофей для загрузки модели");
      return;
    }
    
    if (!file.name.toLowerCase().endsWith(".stl")) {
      setError("Поддерживается только формат STL");
      return;
    }
    
    if (file.size > 500 * 1024 * 1024) {
      setError("Файл слишком большой. Максимальный размер: 500 MB");
      return;
    }
    
    setUploading(true);
    setUploadProgress(0);
    setError("");
    setSuccess("");
    
    const formData = new FormData();
    formData.append("file", file);
    
    try {
      const response = await axios.post(
        `${API_URL}/api/trophies/${selectedTrophy.id}/upload-model`,
        formData,
        {
          headers: { "Content-Type": "multipart/form-data" },
          onUploadProgress: (progressEvent) => {
            const percentCompleted = Math.round(
              (progressEvent.loaded * 100) / (progressEvent.total || 1)
            );
            setUploadProgress(percentCompleted);
          }
        }
      );
      
      setSuccess(`Модель "${response.data.filename}" загружена успешно`);
      loadTrophies();
      setCurrentModelUrl(`${API_URL}/api/models/${selectedTrophy.id}/${response.data.filename}`);
      setActiveTab(1);
      
    } catch (error) {
      setError("Ошибка при загрузке файла");
      console.error(error);
    } finally {
      setUploading(false);
      setUploadProgress(0);
      if (fileInputRef.current) {
        fileInputRef.current.value = "";
      }
    }
  };
  
  const handleDeleteModel = async (trophyId: string, filename: string) => {
    try {
      await axios.delete(`${API_URL}/api/models/${trophyId}/${filename}`);
      setSuccess(`Модель "${filename}" удалена`);
      loadTrophies();
      setCurrentModelUrl("");
      setMeasurementPoints([]);
    } catch (error) {
      setError("Ошибка при удалении модели");
      console.error(error);
    }
  };
  
  const handlePointAdd = useCallback((point: MeasurementPoint) => {
    setMeasurementPoints(prev => {
      const filtered = prev.filter(p => p.type !== point.type);
      return [...filtered, point];
    });
  }, []);
  
  const handlePointUpdate = useCallback((pointId: string, position: [number, number, number]) => {
    setMeasurementPoints(prev => 
      prev.map(p => p.id === pointId ? { ...p, position } : p)
    );
  }, []);
  
  const handlePointRemove = useCallback((pointId: string) => {
    setMeasurementPoints(prev => prev.filter(p => p.id !== pointId));
  }, []);
  
  const calculateFromPoints = async () => {
    try {
      setError("");
      setSuccess("");
      
      const requiredTypes: PointType[] = [
        "calibration1", "calibration2",
        "axis_start", "axis_end",
        "length_start", "length_end",
        "width_left", "width_right"
      ];
      
      const missingTypes = requiredTypes.filter(
        type => !measurementPoints.find(p => p.type === type)
      );
      
      if (missingTypes.length > 0) {
        setError(`Не хватает точек: ${missingTypes.map(t => t.replace("_", " ")).join(", ")}`);
        return;
      }
      
      const getPoint = (type: PointType) => {
        const point = measurementPoints.find(p => p.type === type);
        return {
          x: point!.position[0],
          y: point!.position[1],
          z: point!.position[2]
        };
      };
      
      const data = {
        calibration: {
          point1: getPoint("calibration1"),
          point2: getPoint("calibration2"),
          actual_distance_mm: calibrationDistance
        },
        axis: {
          axis_start: getPoint("axis_start"),
          axis_end: getPoint("axis_end")
        },
        length_start: getPoint("length_start"),
        length_end: getPoint("length_end"),
        width_left: getPoint("width_left"),
        width_right: getPoint("width_right")
      };
      
      const response = await axios.post(`${API_URL}/api/measurements/calculate`, data);
      setMeasurementResult(response.data);
      setSuccess("Измерения рассчитаны успешно");
      
    } catch (error) {
      setError("Ошибка при расчете измерений");
      console.error(error);
    }
  };
  
  const formatFileSize = (bytes: number): string => {
    if (bytes === 0) return "0 Bytes";
    const k = 1024;
    const sizes = ["Bytes", "KB", "MB", "GB"];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i];
  };
  
  const PointSelectionPanel = () => (
    <Paper sx={{ p: 2, mb: 2 }}>
      <Typography variant="subtitle1" gutterBottom>
        Выбор точек измерения
      </Typography>
      
      <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
        <Button size="small" variant={activePointType === "calibration1" ? "contained" : "outlined"} color="secondary" onClick={() => setActivePointType("calibration1")}>Калибровка 1</Button>
        <Button size="small" variant={activePointType === "calibration2" ? "contained" : "outlined"} color="secondary" onClick={() => setActivePointType("calibration2")}>Калибровка 2</Button>
        <Button size="small" variant={activePointType === "axis_start" ? "contained" : "outlined"} color="primary" onClick={() => setActivePointType("axis_start")}>Начало оси</Button>
        <Button size="small" variant={activePointType === "axis_end" ? "contained" : "outlined"} color="primary" onClick={() => setActivePointType("axis_end")}>Конец оси</Button>
        <Button size="small" variant={activePointType === "length_start" ? "contained" : "outlined"} color="success" onClick={() => setActivePointType("length_start")}>Начало длины</Button>
        <Button size="small" variant={activePointType === "length_end" ? "contained" : "outlined"} color="success" onClick={() => setActivePointType("length_end")}>Конец длины</Button>
        <Button size="small" variant={activePointType === "width_left" ? "contained" : "outlined"} color="warning" onClick={() => setActivePointType("width_left")}>Левая ширина</Button>
        <Button size="small" variant={activePointType === "width_right" ? "contained" : "outlined"} color="warning" onClick={() => setActivePointType("width_right")}>Правая ширина</Button>
      </Stack>
      
      {activePointType && (
        <Alert severity="info" sx={{ mt: 2 }}>
          Кликните на 3D модели для установки точки: {activePointType.replace("_", " ")}
        </Alert>
      )}
    </Paper>
  );
  
  return (
    <Box sx={{ flexGrow: 1, bgcolor: "#f5f5f5", minHeight: "100vh" }}>
      <AppBar position="static">
        <Toolbar>
          <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
            🦌 Trophy Measurement System
          </Typography>
          <Chip label="Метод №6" color="secondary" />
        </Toolbar>
      </AppBar>
      
      <Container maxWidth="xl" sx={{ mt: 4, mb: 4 }}>
        {error && (
          <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError("")}>
            {error}
          </Alert>
        )}
        
        {success && (
          <Alert severity="success" sx={{ mb: 2 }} onClose={() => setSuccess("")}>
            {success}
          </Alert>
        )}
        
        <Tabs value={activeTab} onChange={(e, v) => setActiveTab(v)} sx={{ mb: 2 }}>
          <Tab label="Трофеи и модели" />
          <Tab label="3D Viewer" />
          <Tab label="Измерения" />
        </Tabs>
        
        {activeTab === 0 && (
          <Grid container spacing={3}>
            <Grid item xs={12} md={6}>
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    Создание нового трофея
                  </Typography>
                  
                  <TextField fullWidth label="Вид животного" value={animalSpecies} onChange={(e) => setAnimalSpecies(e.target.value)} margin="normal" placeholder="Например: Canis lupus" />
                  <TextField fullWidth label="Дата добычи" type="date" value={huntDate} onChange={(e) => setHuntDate(e.target.value)} margin="normal" InputLabelProps={{ shrink: true }} />
                  <TextField fullWidth label="Место добычи" value={huntLocation} onChange={(e) => setHuntLocation(e.target.value)} margin="normal" />
                  <TextField fullWidth label="Владелец" value={ownerName} onChange={(e) => setOwnerName(e.target.value)} margin="normal" />
                  
                  <Button variant="contained" color="primary" onClick={createTrophy} sx={{ mt: 2 }} fullWidth>
                    Создать трофей
                  </Button>
                </CardContent>
              </Card>
              
              <Card sx={{ mt: 2 }}>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    Список трофеев ({trophies.length})
                  </Typography>
                  
                  <List>
                    {trophies.length === 0 ? (
                      <Typography variant="body2" color="textSecondary">
                        Нет созданных трофеев
                      </Typography>
                    ) : (
                      trophies.map((trophy) => (
                        <React.Fragment key={trophy.id}>
                          <ListItem 
                            button 
                            onClick={() => {
                              setSelectedTrophy(trophy);
                              if (trophy.models.length > 0) {
                                setCurrentModelUrl(`${API_URL}/api/models/${trophy.id}/${trophy.models[0].filename}`);
                              }
                            }}
                            selected={selectedTrophy?.id === trophy.id}
                          >
                            <ListItemText
                              primary={trophy.animal_species}
                              secondary={`${trophy.hunt_date} - ${trophy.hunt_location} (${trophy.models.length} моделей)`}
                            />
                            <Chip label={trophy.status} size="small" />
                          </ListItem>
                          <Divider />
                        </React.Fragment>
                      ))
                    )}
                  </List>
                </CardContent>
              </Card>
            </Grid>
            
            <Grid item xs={12} md={6}>
              {selectedTrophy && (
                <Card>
                  <CardContent>
                    <Typography variant="h6" gutterBottom>
                      Загрузка 3D-модели
                    </Typography>
                    
                    <Typography variant="body2" color="textSecondary" sx={{ mb: 2 }}>
                      Выбран трофей: {selectedTrophy.animal_species}
                    </Typography>
                    
                    <input ref={fileInputRef} type="file" accept=".stl" onChange={handleFileUpload} style={{ display: "none" }} id="stl-upload" />
                    
                    <label htmlFor="stl-upload">
                      <Button variant="contained" component="span" startIcon={<CloudUploadIcon />} disabled={uploading} fullWidth>
                        {uploading ? "Загрузка..." : "Выбрать STL файл"}
                      </Button>
                    </label>
                    
                    {uploading && (
                      <Box sx={{ mt: 2 }}>
                        <LinearProgress variant="determinate" value={uploadProgress} />
                        <Typography variant="body2" sx={{ mt: 1 }}>
                          Загрузка: {uploadProgress}%
                        </Typography>
                      </Box>
                    )}
                    
                    {selectedTrophy.models.length > 0 && (
                      <Box sx={{ mt: 2 }}>
                        <Typography variant="subtitle1" gutterBottom>
                          Загруженные модели:
                        </Typography>
                        <List dense>
                          {selectedTrophy.models.map((model) => (
                            <ListItem key={model.id}>
                              <ListItemText
                                primary={model.filename}
                                secondary={`${model.format.toUpperCase()} | ${model.triangles_count} треугольников | ${formatFileSize(model.file_size)}`}
                              />
                              <IconButton edge="end" aria-label="view" onClick={() => {
                                setCurrentModelUrl(`${API_URL}/api/models/${selectedTrophy.id}/${model.filename}`);
                                setActiveTab(1);
                              }}>
                                <ThreeDRotationIcon />
                              </IconButton>
                              <IconButton edge="end" aria-label="delete" onClick={() => handleDeleteModel(selectedTrophy.id, model.filename)}>
                                <DeleteIcon />
                              </IconButton>
                            </ListItem>
                          ))}
                        </List>
                      </Box>
                    )}
                  </CardContent>
                </Card>
              )}
            </Grid>
          </Grid>
        )}
        
        {activeTab === 1 && (
          <Card>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                3D Viewer
              </Typography>
              
              {currentModelUrl ? (
                <>
                  <PointSelectionPanel />
                  <Box sx={{ height: 600, border: "1px solid #ccc", borderRadius: 1 }}>
                    <ModelViewer
                      modelUrl={currentModelUrl}
                      points={measurementPoints}
                      onPointAdd={handlePointAdd}
                      onPointUpdate={handlePointUpdate}
                      onPointRemove={handlePointRemove}
                      activePointType={activePointType}
                      onActivePointTypeChange={setActivePointType}
                    />
                  </Box>
                </>
              ) : (
                <Alert severity="info">
                  Загрузите STL модель для просмотра в 3D
                </Alert>
              )}
            </CardContent>
          </Card>
        )}
        
        {activeTab === 2 && (
          <Grid container spacing={3}>
            <Grid item xs={12} md={6}>
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    Параметры измерений
                  </Typography>
                  
                  <TextField
                    fullWidth
                    label="Калибровочное расстояние (мм)"
                    type="number"
                    value={calibrationDistance}
                    onChange={(e) => setCalibrationDistance(Number(e.target.value))}
                    margin="normal"
                  />
                  
                  <Button
                    variant="contained"
                    color="primary"
                    onClick={calculateFromPoints}
                    sx={{ mt: 2 }}
                    fullWidth
                    startIcon={<StraightenIcon />}
                  >
                    Рассчитать из 3D точек
                  </Button>
                  
                  <Alert severity="info" sx={{ mt: 2 }}>
                    Точки измерения: {measurementPoints.length}/8
                  </Alert>
                </CardContent>
              </Card>
            </Grid>
            
            <Grid item xs={12} md={6}>
              {measurementResult && (
                <Card>
                  <CardContent>
                    <Typography variant="h6" gutterBottom>
                      Результаты измерений
                    </Typography>
                    
                    <Paper elevation={2} sx={{ p: 2, mb: 2 }}>
                      <Typography variant="body1">
                        Длина: {measurementResult.final_length_cm.toFixed(2)} см
                      </Typography>
                      <Typography variant="body1">
                        Ширина: {measurementResult.final_width_cm.toFixed(2)} см
                      </Typography>
                      <Typography variant="h6" sx={{ mt: 1 }}>
                        Итого: {measurementResult.final_total_cm.toFixed(2)} см
                      </Typography>
                    </Paper>
                    
                    <Typography variant="body2" color="textSecondary">
                      Масштабный коэффициент: {measurementResult.scale_factor.toFixed(4)}
                    </Typography>
                    <Typography variant="body2" color="textSecondary">
                      Отклонение от перпендикуляра: {measurementResult.perpendicular_deviation_degrees.toFixed(1)}°
                    </Typography>
                    
                    {measurementResult.is_width_perpendicular ? (
                      <Alert severity="success" sx={{ mt: 2 }}>
                        ✓ Ширина перпендикулярна оси
                      </Alert>
                    ) : (
                      <Alert severity="warning" sx={{ mt: 2 }}>
                        ⚠ Отклонение от перпендикуляра превышает 5°
                      </Alert>
                    )}
                  </CardContent>
                </Card>
              )}
            </Grid>
          </Grid>
        )}
      </Container>
    </Box>
  );
}

export default App;
EOF

echo "✅ App.tsx исправлен для IP 93.77.162.57"

