from pydantic import BaseModel
from typing import List, Optional


class BoundingBox(BaseModel):
    x: int
    y: int
    width: int
    height: int


class CelebrityMatch(BaseModel):
    id: str
    name: str
    confidence: float
    color: str  # Hex color like "#FF5733"
    bounding_box: BoundingBox
    brief: Optional[str] = None


class RecognitionResponse(BaseModel):
    annotated_image: str  # Base64 encoded PNG
    celebrities: List[CelebrityMatch]


class MovieCredit(BaseModel):
    title: str
    year: int
    role: str


class MusicCredit(BaseModel):
    title: str
    year: int
    type: str  # album, single, etc.


class CelebrityDetails(BaseModel):
    id: str
    name: str
    date_of_birth: Optional[str] = None
    birthplace: Optional[str] = None
    profession: List[str] = []
    biography: str = ""
    movies: List[MovieCredit] = []
    music: List[MusicCredit] = []
    awards: List[str] = []
    image_url: Optional[str] = None
