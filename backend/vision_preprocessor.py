"""
Vision Preprocessor for Screen Reasoning
Handles OCR, UI element detection, and image preprocessing before VLM analysis.
"""

import os
import cv2
import numpy as np
import base64
import tempfile
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass
from io import BytesIO
from PIL import Image, ImageEnhance
import json

# OCR imports
try:
    import pytesseract
    TESSERACT_AVAILABLE = True
except ImportError:
    TESSERACT_AVAILABLE = False
    print("⚠️ Tesseract not available. Install with: pip install pytesseract")

# Computer vision imports
try:
    import easyocr
    EASYOCR_AVAILABLE = True
except ImportError:
    EASYOCR_AVAILABLE = False
    print("⚠️ EasyOCR not available. Install with: pip install easyocr")

@dataclass
class TextRegion:
    text: str
    confidence: float
    bbox: Tuple[int, int, int, int]  # (x1, y1, x2, y2)
    category: str = "text"  # text, heading, button, label, etc.

@dataclass
class UIElement:
    type: str  # button, input, chart, table, menu, etc.
    bbox: Tuple[int, int, int, int]
    confidence: float
    properties: Dict[str, Any]

@dataclass
class VisionPreprocessorResult:
    """Result from vision preprocessing pipeline."""
    # Original image info
    original_size: Tuple[int, int]
    processed_size: Tuple[int, int]
    
    # Text extraction
    text_regions: List[TextRegion]
    extracted_text: str
    
    # UI elements
    ui_elements: List[UIElement]
    
    # Image analysis
    image_quality: Dict[str, float]
    dominant_colors: List[str]
    layout_analysis: Dict[str, Any]
    
    # Processed image (base64 encoded)
    processed_image_base64: str

class VisionPreprocessor:
    """
    Vision preprocessing pipeline for screen reasoning.
    Extracts text, detects UI elements, and prepares structured vision inputs.
    """
    
    def __init__(self):
        self.easyocr_reader = None
        self.ui_detector = None
        
        # Initialize OCR engine
        self._init_ocr()
        
        # UI element detection patterns
        self.ui_patterns = {
            "button": {
                "color_range": [(50, 50, 50), (200, 200, 200)],
                "aspect_ratio": (0.2, 5.0),
                "min_area": 100
            },
            "input_field": {
                "color_range": [(240, 240, 240), (255, 255, 255)],
                "aspect_ratio": (2.0, 20.0),
                "min_area": 200
            },
            "chart": {
                "complexity_threshold": 0.7,
                "min_area": 5000
            }
        }
        
        print("✅ Vision Preprocessor initialized")
        print(f"   📝 Tesseract available: {TESSERACT_AVAILABLE}")
        print(f"   🔍 EasyOCR available: {EASYOCR_AVAILABLE}")
    
    def _init_ocr(self):
        """Initialize OCR engines."""
        if EASYOCR_AVAILABLE:
            try:
                self.easyocr_reader = easyocr.Reader(['en'])
                print("✅ EasyOCR initialized")
            except Exception as e:
                print(f"⚠️ EasyOCR initialization failed: {e}")
                self.easyocr_reader = None
    
    async def process_screen_image(self, image_base64: str, 
                                 enable_ocr: bool = True,
                                 enable_ui_detection: bool = True,
                                 enhance_quality: bool = True) -> VisionPreprocessorResult:
        """
        Main preprocessing pipeline for screen images.
        
        Args:
            image_base64: Base64 encoded image data
            enable_ocr: Whether to perform text extraction
            enable_ui_detection: Whether to detect UI elements
            enhance_quality: Whether to enhance image quality
        """
        
        # Decode image
        image_data = base64.b64decode(image_base64)
        image = Image.open(BytesIO(image_data))
        original_size = image.size
        
        # Convert to OpenCV format for processing
        cv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
        
        # Enhance image quality if requested
        if enhance_quality:
            cv_image = self._enhance_image_quality(cv_image)
        
        processed_image = Image.fromarray(cv2.cvtColor(cv_image, cv2.COLOR_BGR2RGB))
        processed_size = processed_image.size
        
        # Initialize result
        result = VisionPreprocessorResult(
            original_size=original_size,
            processed_size=processed_size,
            text_regions=[],
            extracted_text="",
            ui_elements=[],
            image_quality={},
            dominant_colors=[],
            layout_analysis={},
            processed_image_base64=""
        )
        
        # Perform OCR if enabled
        if enable_ocr:
            result.text_regions, result.extracted_text = await self._extract_text(cv_image)
        
        # Detect UI elements if enabled
        if enable_ui_detection:
            result.ui_elements = await self._detect_ui_elements(cv_image)
        
        # Analyze image properties
        result.image_quality = self._analyze_image_quality(cv_image)
        result.dominant_colors = self._extract_dominant_colors(cv_image)
        result.layout_analysis = self._analyze_layout(cv_image, result.text_regions, result.ui_elements)
        
        # Encode processed image
        result.processed_image_base64 = self._encode_image_to_base64(processed_image)
        
        return result
    
    def _enhance_image_quality(self, image: np.ndarray) -> np.ndarray:
        """Enhance image quality for better OCR and analysis."""
        # Convert to PIL for enhancement
        pil_image = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
        
        # Enhance contrast
        enhancer = ImageEnhance.Contrast(pil_image)
        pil_image = enhancer.enhance(1.2)
        
        # Enhance sharpness
        enhancer = ImageEnhance.Sharpness(pil_image)
        pil_image = enhancer.enhance(1.1)
        
        # Convert back to OpenCV
        return cv2.cvtColor(np.array(pil_image), cv2.COLOR_RGB2BGR)
    
    async def _extract_text(self, image: np.ndarray) -> Tuple[List[TextRegion], str]:
        """Extract text using available OCR engines."""
        text_regions = []
        all_text = []
        
        # Try EasyOCR first (better for diverse layouts)
        if self.easyocr_reader:
            try:
                results = self.easyocr_reader.readtext(image)
                for (bbox, text, confidence) in results:
                    if confidence > 0.5 and text.strip():
                        # Convert bbox format
                        x1, y1 = int(min(bbox, key=lambda x: x[0])[0]), int(min(bbox, key=lambda x: x[1])[1])
                        x2, y2 = int(max(bbox, key=lambda x: x[0])[0]), int(max(bbox, key=lambda x: x[1])[1])
                        
                        text_regions.append(TextRegion(
                            text=text.strip(),
                            confidence=confidence,
                            bbox=(x1, y1, x2, y2),
                            category=self._classify_text_type(text, (x2-x1, y2-y1))
                        ))
                        all_text.append(text.strip())
                        
            except Exception as e:
                print(f"⚠️ EasyOCR failed: {e}")
        
        # Fallback to Tesseract if available and EasyOCR didn't find much
        if TESSERACT_AVAILABLE and len(text_regions) < 5:
            try:
                # Get text with bounding boxes
                data = pytesseract.image_to_data(image, output_type=pytesseract.Output.DICT)
                
                for i in range(len(data['text'])):
                    text = data['text'][i].strip()
                    conf = int(data['conf'][i])
                    
                    if conf > 50 and text:
                        x, y, w, h = data['left'][i], data['top'][i], data['width'][i], data['height'][i]
                        
                        text_regions.append(TextRegion(
                            text=text,
                            confidence=conf / 100.0,
                            bbox=(x, y, x + w, y + h),
                            category=self._classify_text_type(text, (w, h))
                        ))
                        all_text.append(text)
                        
            except Exception as e:
                print(f"⚠️ Tesseract failed: {e}")
        
        # Combine and clean text
        extracted_text = self._clean_and_organize_text(text_regions)
        
        return text_regions, extracted_text
    
    def _classify_text_type(self, text: str, size: Tuple[int, int]) -> str:
        """Classify text based on content and size."""
        width, height = size
        
        # Large text likely headings
        if height > 20:
            return "heading"
        
        # Button-like text
        if any(keyword in text.lower() for keyword in ['click', 'submit', 'cancel', 'ok', 'yes', 'no']):
            return "button"
        
        # Form labels
        if text.endswith(':') or any(keyword in text.lower() for keyword in ['name', 'email', 'password']):
            return "label"
        
        # Menu items
        if width < 200 and any(keyword in text.lower() for keyword in ['file', 'edit', 'view', 'help']):
            return "menu"
        
        return "text"
    
    async def _detect_ui_elements(self, image: np.ndarray) -> List[UIElement]:
        """Detect UI elements using computer vision techniques."""
        ui_elements = []
        
        # Convert to grayscale for analysis
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Detect buttons using edge detection and contours
        buttons = self._detect_buttons(gray)
        ui_elements.extend(buttons)
        
        # Detect input fields
        input_fields = self._detect_input_fields(gray)
        ui_elements.extend(input_fields)
        
        # Detect potential charts/graphs
        charts = self._detect_charts(image)
        ui_elements.extend(charts)
        
        return ui_elements
    
    def _detect_buttons(self, gray_image: np.ndarray) -> List[UIElement]:
        """Detect button-like elements."""
        buttons = []
        
        # Use adaptive threshold to find rectangular regions
        thresh = cv2.adaptiveThreshold(gray_image, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2)
        
        # Find contours
        contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        for contour in contours:
            # Get bounding rectangle
            x, y, w, h = cv2.boundingRect(contour)
            
            # Filter by size and aspect ratio
            if (w * h > self.ui_patterns["button"]["min_area"] and 
                self.ui_patterns["button"]["aspect_ratio"][0] <= w/h <= self.ui_patterns["button"]["aspect_ratio"][1]):
                
                # Calculate confidence based on rectangularity
                area = cv2.contourArea(contour)
                rect_area = w * h
                confidence = area / rect_area if rect_area > 0 else 0
                
                if confidence > 0.7:
                    buttons.append(UIElement(
                        type="button",
                        bbox=(x, y, x + w, y + h),
                        confidence=confidence,
                        properties={"width": w, "height": h}
                    ))
        
        return buttons
    
    def _detect_input_fields(self, gray_image: np.ndarray) -> List[UIElement]:
        """Detect input field elements."""
        fields = []
        
        # Look for horizontal white/light regions (typical input fields)
        thresh = cv2.threshold(gray_image, 240, 255, cv2.THRESH_BINARY)[1]
        
        # Morphological operations to clean up
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (20, 5))
        morphed = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)
        
        contours, _ = cv2.findContours(morphed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        for contour in contours:
            x, y, w, h = cv2.boundingRect(contour)
            
            # Filter by aspect ratio (input fields are typically wide)
            if (w * h > self.ui_patterns["input_field"]["min_area"] and 
                self.ui_patterns["input_field"]["aspect_ratio"][0] <= w/h <= self.ui_patterns["input_field"]["aspect_ratio"][1]):
                
                confidence = min(1.0, (w/h) / 10.0)  # Higher confidence for wider fields
                
                fields.append(UIElement(
                    type="input_field",
                    bbox=(x, y, x + w, y + h),
                    confidence=confidence,
                    properties={"width": w, "height": h}
                ))
        
        return fields
    
    def _detect_charts(self, image: np.ndarray) -> List[UIElement]:
        """Detect chart/graph elements."""
        charts = []
        
        # Convert to HSV for better color analysis
        hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
        
        # Look for regions with high color variance (typical of charts)
        height, width = image.shape[:2]
        
        # Divide image into regions and analyze color complexity
        region_size = 100
        for y in range(0, height - region_size, region_size // 2):
            for x in range(0, width - region_size, region_size // 2):
                region = hsv[y:y + region_size, x:x + region_size]
                
                # Calculate color variance
                std_dev = np.std(region.reshape(-1, 3), axis=0)
                complexity = np.mean(std_dev) / 255.0
                
                # If region has high color complexity, might be a chart
                if complexity > self.ui_patterns["chart"]["complexity_threshold"]:
                    area = region_size * region_size
                    if area > self.ui_patterns["chart"]["min_area"]:
                        charts.append(UIElement(
                            type="chart",
                            bbox=(x, y, x + region_size, y + region_size),
                            confidence=min(1.0, complexity),
                            properties={"color_complexity": complexity}
                        ))
        
        return charts
    
    def _analyze_image_quality(self, image: np.ndarray) -> Dict[str, float]:
        """Analyze image quality metrics."""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Calculate sharpness using Laplacian variance
        sharpness = cv2.Laplacian(gray, cv2.CV_64F).var()
        
        # Calculate brightness
        brightness = np.mean(gray) / 255.0
        
        # Calculate contrast
        contrast = gray.std() / 255.0
        
        return {
            "sharpness": min(1.0, sharpness / 1000.0),
            "brightness": brightness,
            "contrast": contrast
        }
    
    def _extract_dominant_colors(self, image: np.ndarray) -> List[str]:
        """Extract dominant colors from image."""
        # Reshape image to list of pixels
        pixels = image.reshape(-1, 3)
        
        # Use k-means to find dominant colors
        try:
            from sklearn.cluster import KMeans
            
            kmeans = KMeans(n_clusters=5, random_state=42)
            kmeans.fit(pixels)
            
            colors = []
            for color in kmeans.cluster_centers_:
                # Convert BGR to hex
                hex_color = "#{:02x}{:02x}{:02x}".format(int(color[2]), int(color[1]), int(color[0]))
                colors.append(hex_color)
            
            return colors
            
        except ImportError:
            # Fallback: simple color analysis
            mean_color = np.mean(pixels, axis=0)
            hex_color = "#{:02x}{:02x}{:02x}".format(int(mean_color[2]), int(mean_color[1]), int(mean_color[0]))
            return [hex_color]
    
    def _analyze_layout(self, image: np.ndarray, text_regions: List[TextRegion], ui_elements: List[UIElement]) -> Dict[str, Any]:
        """Analyze overall layout structure."""
        height, width = image.shape[:2]
        
        # Count elements by regions
        top_half = sum(1 for tr in text_regions if tr.bbox[1] < height // 2)
        bottom_half = len(text_regions) - top_half
        
        left_half = sum(1 for tr in text_regions if tr.bbox[0] < width // 2)
        right_half = len(text_regions) - left_half
        
        return {
            "total_text_regions": len(text_regions),
            "total_ui_elements": len(ui_elements),
            "text_distribution": {
                "top_half": top_half,
                "bottom_half": bottom_half,
                "left_half": left_half,
                "right_half": right_half
            },
            "layout_type": self._determine_layout_type(text_regions, ui_elements, (width, height))
        }
    
    def _determine_layout_type(self, text_regions: List[TextRegion], ui_elements: List[UIElement], size: Tuple[int, int]) -> str:
        """Determine the type of layout/interface."""
        width, height = size
        
        # Count different element types
        buttons = sum(1 for el in ui_elements if el.type == "button")
        inputs = sum(1 for el in ui_elements if el.type == "input_field")
        charts = sum(1 for el in ui_elements if el.type == "chart")
        
        headings = sum(1 for tr in text_regions if tr.category == "heading")
        
        # Classify layout
        if charts > 0:
            return "dashboard"
        elif inputs > 2:
            return "form"
        elif buttons > 3:
            return "application_ui"
        elif headings > 0 and len(text_regions) > 10:
            return "document"
        elif width > height * 1.5:  # Wide aspect ratio
            return "browser"
        else:
            return "general"
    
    def _clean_and_organize_text(self, text_regions: List[TextRegion]) -> str:
        """Clean and organize extracted text into readable format."""
        if not text_regions:
            return ""
        
        # Sort by position (top to bottom, left to right)
        sorted_regions = sorted(text_regions, key=lambda tr: (tr.bbox[1], tr.bbox[0]))
        
        # Group by categories
        headings = [tr for tr in sorted_regions if tr.category == "heading"]
        buttons = [tr for tr in sorted_regions if tr.category == "button"]
        labels = [tr for tr in sorted_regions if tr.category == "label"]
        regular_text = [tr for tr in sorted_regions if tr.category == "text"]
        
        # Build organized text
        organized = []
        
        if headings:
            organized.append("=== HEADINGS ===")
            organized.extend([h.text for h in headings])
            organized.append("")
        
        if regular_text:
            organized.append("=== MAIN CONTENT ===")
            organized.extend([t.text for t in regular_text])
            organized.append("")
        
        if labels:
            organized.append("=== LABELS/FIELDS ===")
            organized.extend([l.text for l in labels])
            organized.append("")
        
        if buttons:
            organized.append("=== INTERACTIVE ELEMENTS ===")
            organized.extend([b.text for b in buttons])
        
        return "\n".join(organized)
    
    def _encode_image_to_base64(self, image: Image.Image) -> str:
        """Encode PIL image to base64."""
        buffer = BytesIO()
        image.save(buffer, format="PNG")
        return base64.b64encode(buffer.getvalue()).decode('utf-8')
    
    def create_structured_prompt_context(self, result: VisionPreprocessorResult, user_question: str) -> Dict[str, Any]:
        """Create structured context for prompt building."""
        return {
            "image_info": {
                "original_size": result.original_size,
                "processed_size": result.processed_size,
                "quality": result.image_quality,
                "layout_type": result.layout_analysis.get("layout_type", "unknown")
            },
            "extracted_text": {
                "full_text": result.extracted_text,
                "text_regions_count": len(result.text_regions),
                "has_headings": any(tr.category == "heading" for tr in result.text_regions),
                "has_buttons": any(tr.category == "button" for tr in result.text_regions)
            },
            "ui_elements": {
                "total_count": len(result.ui_elements),
                "buttons": len([el for el in result.ui_elements if el.type == "button"]),
                "input_fields": len([el for el in result.ui_elements if el.type == "input_field"]),
                "charts": len([el for el in result.ui_elements if el.type == "chart"])
            },
            "user_question": user_question,
            "analysis_confidence": {
                "text_extraction": np.mean([tr.confidence for tr in result.text_regions]) if result.text_regions else 0.0,
                "ui_detection": np.mean([el.confidence for el in result.ui_elements]) if result.ui_elements else 0.0
            }
        }

# Global preprocessor instance
vision_preprocessor = VisionPreprocessor()

def get_vision_preprocessor() -> VisionPreprocessor:
    """Get global vision preprocessor instance."""
    return vision_preprocessor