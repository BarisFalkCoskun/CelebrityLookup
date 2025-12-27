import cv2
import numpy as np
from PIL import Image
from rembg import remove, new_session
import face_recognition
from typing import List, Dict, Tuple, Optional
import os
import json


class CelebrityPipeline:
    """
    Main ML pipeline for celebrity recognition and segmentation.

    Features:
    - Face detection and recognition using face_recognition (dlib)
    - Person segmentation using rembg (U2-Net)
    - Brooklyn Nine-Nine style cutout effects
    - Colored edge drawing around identified celebrities
    - Name label overlay
    """

    # Distinct colors for multiple people (vibrant, easily distinguishable)
    COLORS = [
        "#FF6B6B",  # Coral Red
        "#4ECDC4",  # Teal
        "#FFE66D",  # Yellow
        "#95E1D3",  # Mint
        "#F38181",  # Salmon
        "#AA96DA",  # Lavender
        "#FCBAD3",  # Pink
        "#A8D8EA",  # Light Blue
        "#FF9F43",  # Orange
        "#6C5CE7",  # Purple
    ]

    # Brooklyn Nine-Nine style background gradients (dark to vibrant)
    B99_BACKGROUNDS = {
        "#FF6B6B": [(20, 20, 40), (180, 60, 60)],      # Dark blue to coral
        "#4ECDC4": [(20, 30, 30), (60, 160, 150)],     # Dark to teal
        "#FFE66D": [(30, 25, 15), (200, 180, 80)],     # Dark to yellow
        "#95E1D3": [(15, 30, 25), (120, 180, 170)],    # Dark to mint
        "#F38181": [(25, 15, 20), (190, 100, 100)],    # Dark to salmon
        "#AA96DA": [(25, 20, 35), (140, 120, 180)],    # Dark to lavender
        "#FCBAD3": [(30, 20, 25), (200, 150, 170)],    # Dark to pink
        "#A8D8EA": [(15, 25, 35), (130, 170, 190)],    # Dark to light blue
        "#FF9F43": [(30, 20, 10), (200, 130, 50)],     # Dark to orange
        "#6C5CE7": [(20, 15, 35), (90, 75, 190)],      # Dark to purple
    }

    def __init__(self, celebrity_encodings_path: Optional[str] = None):
        """
        Initialize the ML pipeline.

        Args:
            celebrity_encodings_path: Path to directory containing celebrity face encodings
        """
        print("Initializing face recognition...")

        # Initialize segmentation session (high quality for cutouts)
        print("Loading segmentation model...")
        self.seg_session = new_session("u2net_human_seg")
        print("Segmentation model loaded.")

        # Load celebrity face encodings
        if celebrity_encodings_path is None:
            base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            celebrity_encodings_path = os.path.join(base_dir, "data", "celebrity_encodings")

        self.celebrity_db = self._load_celebrity_encodings(celebrity_encodings_path)
        print(f"Loaded {len(self.celebrity_db)} celebrity encodings.")

    def _load_celebrity_encodings(self, path: str) -> Dict:
        """Load pre-computed celebrity face encodings."""
        db = {}
        index_path = os.path.join(path, "index.json")

        if os.path.exists(index_path):
            with open(index_path, 'r') as f:
                index = json.load(f)

            for celeb_id, info in index.items():
                encoding_file = os.path.join(path, f"{celeb_id}.npy")
                if os.path.exists(encoding_file):
                    db[celeb_id] = {
                        "name": info["name"],
                        "encoding": np.load(encoding_file)
                    }

        return db

    def _match_face(
        self,
        face_encoding: np.ndarray,
        tolerance: float = 0.6
    ) -> Optional[Tuple[str, str, float]]:
        """
        Match face encoding against celebrity database.

        Args:
            face_encoding: 128-dimensional face embedding from face_recognition
            tolerance: Maximum distance for a match (lower = stricter)

        Returns:
            Tuple of (celebrity_id, name, confidence) or None if no match
        """
        best_match = None
        best_distance = tolerance

        for celeb_id, data in self.celebrity_db.items():
            # Calculate face distance (lower = more similar)
            distance = face_recognition.face_distance([data["encoding"]], face_encoding)[0]

            if distance < best_distance:
                best_distance = distance
                # Convert distance to confidence (0-1, higher = better)
                confidence = 1.0 - distance
                best_match = (celeb_id, data["name"], float(confidence))

        return best_match

    def _segment_person_high_quality(
        self,
        image: np.ndarray,
        face_location: Tuple[int, int, int, int]
    ) -> Tuple[np.ndarray, Tuple[int, int, int, int]]:
        """
        High-quality person segmentation with refined edges.

        Args:
            image: Input image (RGB)
            face_location: Face location (top, right, bottom, left) from face_recognition

        Returns:
            Tuple of (alpha mask 0-255, crop_box)
        """
        h, w = image.shape[:2]
        top, right, bottom, left = face_location

        # Expand bounding box to capture full person
        face_width = right - left
        face_height = bottom - top

        # Generous body region estimate
        body_x1 = max(0, left - int(face_width * 1.5))
        body_y1 = max(0, top - int(face_height * 0.8))
        body_x2 = min(w, right + int(face_width * 1.5))
        body_y2 = min(h, bottom + int(face_height * 8))  # Full body

        crop_box = (body_x1, body_y1, body_x2, body_y2)

        # Crop region
        crop = image[body_y1:body_y2, body_x1:body_x2]
        pil_crop = Image.fromarray(crop)

        # Get alpha mask using rembg (returns RGBA)
        result = remove(pil_crop, session=self.seg_session, alpha_matting=True,
                       alpha_matting_foreground_threshold=240,
                       alpha_matting_background_threshold=10,
                       alpha_matting_erode_size=10)

        # Extract alpha channel
        result_np = np.array(result)
        if result_np.shape[2] == 4:
            alpha = result_np[:, :, 3]
        else:
            # Fallback to mask mode
            mask_result = remove(pil_crop, session=self.seg_session, only_mask=True)
            alpha = np.array(mask_result)

        return alpha, crop_box

    def _segment_person(
        self,
        image: np.ndarray,
        face_location: Tuple[int, int, int, int],
        padding: int = 80
    ) -> np.ndarray:
        """
        Segment a person given their face location.

        Args:
            image: Input image (RGB)
            face_location: Face location (top, right, bottom, left) from face_recognition
            padding: Padding around face to capture full body

        Returns:
            Binary mask of the segmented person
        """
        h, w = image.shape[:2]
        top, right, bottom, left = face_location

        # Expand bounding box to capture more of the person
        face_width = right - left
        face_height = bottom - top

        # Estimate body region based on face position
        body_x1 = max(0, left - face_width)
        body_y1 = max(0, top - int(face_height * 0.5))
        body_x2 = min(w, right + face_width)
        body_y2 = min(h, bottom + int(face_height * 6))  # Extend down for body

        # Crop and segment
        crop = image[body_y1:body_y2, body_x1:body_x2]
        pil_crop = Image.fromarray(crop)

        # Get mask using rembg
        result = remove(pil_crop, session=self.seg_session, only_mask=True)
        mask = np.array(result)

        # Create full-size mask
        full_mask = np.zeros((h, w), dtype=np.uint8)
        full_mask[body_y1:body_y2, body_x1:body_x2] = mask

        return full_mask

    def _hex_to_bgr(self, color_hex: str) -> Tuple[int, int, int]:
        """Convert hex color to BGR tuple."""
        color_hex = color_hex.lstrip('#')
        rgb = tuple(int(color_hex[i:i+2], 16) for i in (0, 2, 4))
        return (rgb[2], rgb[1], rgb[0])

    def _hex_to_rgb(self, color_hex: str) -> Tuple[int, int, int]:
        """Convert hex color to RGB tuple."""
        color_hex = color_hex.lstrip('#')
        return tuple(int(color_hex[i:i+2], 16) for i in (0, 2, 4))

    def _create_gradient_background(
        self,
        width: int,
        height: int,
        color_hex: str
    ) -> np.ndarray:
        """Create a B99-style gradient background."""
        # Normalize color format
        if not color_hex.startswith('#'):
            color_hex = '#' + color_hex

        if color_hex in self.B99_BACKGROUNDS:
            color1, color2 = self.B99_BACKGROUNDS[color_hex]
        else:
            # Fallback gradient
            color1 = (20, 20, 30)
            color2 = self._hex_to_rgb(color_hex)

        # Create vertical gradient
        gradient = np.zeros((height, width, 3), dtype=np.uint8)
        for y in range(height):
            ratio = y / height
            r = int(color1[0] * (1 - ratio) + color2[0] * ratio)
            g = int(color1[1] * (1 - ratio) + color2[1] * ratio)
            b = int(color1[2] * (1 - ratio) + color2[2] * ratio)
            gradient[y, :] = [r, g, b]

        return gradient

    def _draw_improved_edge(
        self,
        image: np.ndarray,
        mask: np.ndarray,
        color_hex: str,
        thickness: int = 6,
        glow_size: int = 15
    ) -> np.ndarray:
        """
        Draw an improved colored edge with glow effect.

        Args:
            image: Input image (BGR)
            mask: Binary/alpha mask of the person
            color_hex: Hex color code for the edge
            thickness: Edge thickness in pixels
            glow_size: Size of the outer glow

        Returns:
            Image with colored edge drawn
        """
        bgr = self._hex_to_bgr(color_hex)

        # Threshold mask if it's alpha (0-255)
        if mask.max() > 1:
            binary_mask = (mask > 127).astype(np.uint8) * 255
        else:
            binary_mask = mask

        # Smooth the mask edges
        binary_mask = cv2.GaussianBlur(binary_mask, (5, 5), 0)
        _, binary_mask = cv2.threshold(binary_mask, 127, 255, cv2.THRESH_BINARY)

        # Find contours
        contours, _ = cv2.findContours(binary_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        if not contours:
            return image

        result = image.copy()

        # Create glow effect using dilated contours with decreasing opacity
        for i in range(glow_size, 0, -2):
            overlay = result.copy()
            cv2.drawContours(overlay, contours, -1, bgr, thickness + i * 2)
            alpha = 0.05 + (0.15 * (glow_size - i) / glow_size)
            result = cv2.addWeighted(overlay, alpha, result, 1 - alpha, 0)

        # Draw main solid edge
        cv2.drawContours(result, contours, -1, bgr, thickness)

        # Draw thin white highlight on the inside
        dilated_mask = cv2.dilate(binary_mask, np.ones((3, 3), np.uint8), iterations=1)
        inner_contours, _ = cv2.findContours(dilated_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cv2.drawContours(result, inner_contours, -1, (255, 255, 255), max(1, thickness // 4))

        return result

    def _draw_colored_edge(
        self,
        image: np.ndarray,
        mask: np.ndarray,
        color_hex: str,
        thickness: int = 5
    ) -> np.ndarray:
        """
        Draw a colored edge/outline around a segmented person.

        Args:
            image: Input image (BGR)
            mask: Binary mask of the person
            color_hex: Hex color code for the edge
            thickness: Edge thickness in pixels

        Returns:
            Image with colored edge drawn
        """
        return self._draw_improved_edge(image, mask, color_hex, thickness)

    def _add_name_label(
        self,
        image: np.ndarray,
        name: str,
        face_location: Tuple[int, int, int, int],
        color_hex: str
    ) -> np.ndarray:
        """
        Add a stylized name label near the person.

        Args:
            image: Input image (BGR)
            name: Celebrity name to display
            face_location: Face location (top, right, bottom, left)
            color_hex: Matching color for the label

        Returns:
            Image with name label added
        """
        bgr = self._hex_to_bgr(color_hex)

        top, right, bottom, left = face_location
        center_x = (left + right) // 2

        # Position label below the face
        label_y = min(bottom + 40, image.shape[0] - 20)

        # Get text size
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = 0.9
        thickness = 2
        (text_w, text_h), baseline = cv2.getTextSize(name, font, font_scale, thickness)

        # Calculate pill/badge dimensions
        padding_x = 15
        padding_y = 10
        pill_x1 = max(0, center_x - text_w // 2 - padding_x)
        pill_x2 = min(image.shape[1], center_x + text_w // 2 + padding_x)
        pill_y1 = label_y - text_h - padding_y
        pill_y2 = label_y + padding_y + baseline

        result = image.copy()

        # Draw shadow
        shadow_offset = 3
        cv2.rectangle(
            result,
            (pill_x1 + shadow_offset, pill_y1 + shadow_offset),
            (pill_x2 + shadow_offset, pill_y2 + shadow_offset),
            (30, 30, 30),
            -1
        )

        # Draw main pill background
        cv2.rectangle(result, (pill_x1, pill_y1), (pill_x2, pill_y2), bgr, -1)

        # Draw border
        cv2.rectangle(result, (pill_x1, pill_y1), (pill_x2, pill_y2), (255, 255, 255), 2)

        # Draw text
        text_x = center_x - text_w // 2
        text_y = label_y

        # Text shadow
        cv2.putText(result, name, (text_x + 1, text_y + 1), font, font_scale, (0, 0, 0), thickness + 1)
        # Main text
        cv2.putText(result, name, (text_x, text_y), font, font_scale, (255, 255, 255), thickness)

        return result

    def _add_b99_name_label(
        self,
        image: np.ndarray,
        name: str,
        color_hex: str,
        position: str = "bottom"
    ) -> np.ndarray:
        """
        Add Brooklyn Nine-Nine style name label.

        Args:
            image: Input image (BGR or RGB)
            name: Name to display
            color_hex: Color for the name
            position: "bottom" or "center"

        Returns:
            Image with B99-style name
        """
        h, w = image.shape[:2]
        result = image.copy()

        # Use a large, bold font
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = min(w, h) / 300  # Scale based on image size
        thickness = max(2, int(font_scale * 2))

        # Get text size
        (text_w, text_h), baseline = cv2.getTextSize(name.upper(), font, font_scale, thickness)

        # Position
        if position == "bottom":
            text_x = (w - text_w) // 2
            text_y = h - int(h * 0.1)
        else:
            text_x = (w - text_w) // 2
            text_y = (h + text_h) // 2

        # Draw text shadow (multiple layers for depth)
        for offset in range(8, 0, -2):
            shadow_alpha = 0.3 - (offset * 0.03)
            overlay = result.copy()
            cv2.putText(overlay, name.upper(), (text_x + offset, text_y + offset),
                       font, font_scale, (0, 0, 0), thickness + 2)
            result = cv2.addWeighted(overlay, shadow_alpha, result, 1 - shadow_alpha, 0)

        # Main text with color
        rgb = self._hex_to_rgb(color_hex)
        cv2.putText(result, name.upper(), (text_x, text_y), font, font_scale,
                   rgb, thickness)

        # White outline for pop
        cv2.putText(result, name.upper(), (text_x, text_y), font, font_scale,
                   (255, 255, 255), max(1, thickness // 2))

        return result

    def process(self, image: np.ndarray) -> Dict:
        """
        Main processing pipeline.

        Steps:
        1. Detect all faces in the image
        2. For each face, try to match against celebrity database
        3. Segment identified celebrities
        4. Draw colored edges and name labels

        Args:
            image: Input image (BGR format from OpenCV)

        Returns:
            Dictionary containing:
            - annotated_image: Image with edges and labels
            - matches: List of matched celebrities with metadata
        """
        results = {
            "matches": [],
            "annotated_image": image.copy()
        }

        # Convert BGR to RGB for face_recognition
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

        # Detect faces
        face_locations = face_recognition.face_locations(rgb_image)
        face_encodings = face_recognition.face_encodings(rgb_image, face_locations)

        if not face_locations:
            return results

        # Process each face
        color_idx = 0
        for face_location, face_encoding in zip(face_locations, face_encodings):
            # Try to match with celebrity database
            match = self._match_face(face_encoding)

            if match:
                celeb_id, name, confidence = match
                color = self.COLORS[color_idx % len(self.COLORS)]
                color_idx += 1

                # Segment the person
                mask = self._segment_person(rgb_image, face_location)

                # Draw colored edge
                results["annotated_image"] = self._draw_colored_edge(
                    results["annotated_image"], mask, color
                )

                # Add name label
                results["annotated_image"] = self._add_name_label(
                    results["annotated_image"], name, face_location, color
                )

                # Convert face_location to bbox format
                top, right, bottom, left = face_location
                results["matches"].append({
                    "celebrity_id": celeb_id,
                    "name": name,
                    "confidence": confidence,
                    "color": color,
                    "bbox": {
                        "x": left,
                        "y": top,
                        "width": right - left,
                        "height": bottom - top
                    }
                })

        return results

    def process_fast(self, image: np.ndarray) -> Dict:
        """
        Fast processing for real-time use (no segmentation).

        Args:
            image: Input image (BGR format from OpenCV)

        Returns:
            Dictionary with face locations and celebrity matches
        """
        results = {
            "faces": [],
            "matches": []
        }

        # Convert BGR to RGB for face_recognition
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

        # Use faster model for real-time (CNN vs HOG)
        # HOG is faster, CNN is more accurate
        face_locations = face_recognition.face_locations(rgb_image, model="hog")
        face_encodings = face_recognition.face_encodings(rgb_image, face_locations)

        color_idx = 0
        for face_location, face_encoding in zip(face_locations, face_encodings):
            top, right, bottom, left = face_location
            face_data = {
                "bbox": {
                    "x": left,
                    "y": top,
                    "width": right - left,
                    "height": bottom - top
                }
            }
            results["faces"].append(face_data)

            # Try to match with celebrity database
            match = self._match_face(face_encoding)
            if match:
                celeb_id, name, confidence = match
                color = self.COLORS[color_idx % len(self.COLORS)]
                color_idx += 1

                results["matches"].append({
                    "celebrity_id": celeb_id,
                    "name": name,
                    "confidence": confidence,
                    "color": color,
                    "face_index": len(results["faces"]) - 1,
                    "bbox": face_data["bbox"]
                })

        return results

    def generate_cutout(
        self,
        image: np.ndarray,
        face_box: Dict[str, int],
        color_hex: str,
        name: str
    ) -> Dict:
        """
        Generate Brooklyn Nine-Nine style cutout.

        Args:
            image: Input image (BGR)
            face_box: Face bounding box {x, y, width, height}
            color_hex: Color theme for the cutout
            name: Celebrity name

        Returns:
            Dictionary with:
            - cutout_image: RGBA image of just the person
            - presentation_image: Full B99-style presentation
        """
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

        # Convert face_box to face_location format
        face_location = (
            face_box["y"],  # top
            face_box["x"] + face_box["width"],  # right
            face_box["y"] + face_box["height"],  # bottom
            face_box["x"]  # left
        )

        # High-quality segmentation
        alpha, crop_box = self._segment_person_high_quality(rgb_image, face_location)
        x1, y1, x2, y2 = crop_box

        # Get cropped person
        person_crop = rgb_image[y1:y2, x1:x2].copy()

        # Create RGBA cutout
        cutout_rgba = np.zeros((person_crop.shape[0], person_crop.shape[1], 4), dtype=np.uint8)
        cutout_rgba[:, :, :3] = person_crop
        cutout_rgba[:, :, 3] = alpha

        # Create B99-style presentation
        # Calculate dimensions - make it portrait oriented
        crop_h, crop_w = person_crop.shape[:2]
        target_h = max(crop_h, int(crop_h * 1.3))
        target_w = max(crop_w, int(target_h * 0.7))

        # Create gradient background
        background = self._create_gradient_background(target_w, target_h, color_hex)

        # Calculate position to center the person
        paste_x = (target_w - crop_w) // 2
        paste_y = int(target_h * 0.1)  # Slight offset from top

        # Ensure we don't exceed bounds
        paste_y = min(paste_y, target_h - crop_h)
        if paste_y < 0:
            paste_y = 0

        # Create presentation with alpha blending
        presentation = background.copy()

        # Blend person onto background using alpha
        alpha_normalized = alpha.astype(float) / 255.0

        for c in range(3):
            region = presentation[paste_y:paste_y+crop_h, paste_x:paste_x+crop_w, c]
            person_channel = person_crop[:, :, c]
            blended = (person_channel * alpha_normalized + region * (1 - alpha_normalized))
            presentation[paste_y:paste_y+crop_h, paste_x:paste_x+crop_w, c] = blended.astype(np.uint8)

        # Draw stylized edge around person in presentation
        presentation_mask = np.zeros((target_h, target_w), dtype=np.uint8)
        presentation_mask[paste_y:paste_y+crop_h, paste_x:paste_x+crop_w] = alpha
        presentation = self._draw_improved_edge(presentation, presentation_mask, color_hex, thickness=4, glow_size=20)

        # Add B99-style name
        presentation = self._add_b99_name_label(presentation, name, color_hex)

        # Convert presentation to BGR for encoding
        presentation_bgr = cv2.cvtColor(presentation, cv2.COLOR_RGB2BGR)

        return {
            "cutout_rgba": cutout_rgba,
            "presentation_rgb": presentation,
            "presentation_bgr": presentation_bgr
        }

    def get_face_encoding(self, image: np.ndarray) -> Optional[np.ndarray]:
        """
        Extract face encoding from an image (for building celebrity database).

        Args:
            image: Input image (BGR from OpenCV)

        Returns:
            128-dimensional face embedding or None if no face detected
        """
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        face_encodings = face_recognition.face_encodings(rgb_image)

        if face_encodings:
            return face_encodings[0]
        return None
