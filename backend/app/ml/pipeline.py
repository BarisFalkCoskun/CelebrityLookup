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

    def __init__(self, celebrity_encodings_path: Optional[str] = None):
        """
        Initialize the ML pipeline.

        Args:
            celebrity_encodings_path: Path to directory containing celebrity face encodings
        """
        print("Initializing face recognition...")

        # Initialize segmentation session
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
        bgr = self._hex_to_bgr(color_hex)

        # Find contours
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        if not contours:
            return image

        result = image.copy()

        # Draw outer glow (thicker, semi-transparent)
        overlay = image.copy()
        cv2.drawContours(overlay, contours, -1, bgr, thickness + 8)
        result = cv2.addWeighted(overlay, 0.3, result, 0.7, 0)

        # Draw main edge
        cv2.drawContours(result, contours, -1, bgr, thickness)

        # Draw inner highlight (thin white line for pop effect)
        cv2.drawContours(result, contours, -1, (255, 255, 255), max(1, thickness // 3))

        return result

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
