from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import numpy as np
import cv2
import base64
from contextlib import asynccontextmanager

from app.ml.pipeline import CelebrityPipeline
from app.celebrity_db import get_celebrity_info, list_celebrities, add_celebrity
from app.models import RecognitionResponse, CelebrityMatch, BoundingBox, CelebrityDetails
from app.database import init_db


# Global pipeline instance
pipeline = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize resources on startup."""
    global pipeline
    print("Initializing Celebrity Lookup API...")

    # Initialize database
    init_db()

    # Initialize ML pipeline
    pipeline = CelebrityPipeline()

    print("API ready!")
    yield

    # Cleanup on shutdown
    print("Shutting down...")


app = FastAPI(
    title="Celebrity Lookup API",
    description="Identify celebrities in photos with colored outlines and detailed information",
    version="1.0.0",
    lifespan=lifespan
)

# Configure CORS for iOS app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "service": "Celebrity Lookup API",
        "version": "1.0.0"
    }


@app.get("/stats")
async def get_stats():
    """Get API statistics."""
    return {
        "celebrities_in_database": len(pipeline.celebrity_db) if pipeline else 0,
        "available_colors": len(CelebrityPipeline.COLORS)
    }


@app.post("/recognize", response_model=RecognitionResponse)
async def recognize_celebrities(image: UploadFile = File(...)):
    """
    Process an image to detect and identify celebrities.

    - Detects all faces in the image
    - Matches faces against the celebrity database
    - Segments identified celebrities with colored edges
    - Returns annotated image and celebrity information

    **Request:** Multipart form with image file

    **Response:**
    - `annotated_image`: Base64 encoded PNG with colored edges
    - `celebrities`: List of identified celebrities with confidence scores
    """
    if pipeline is None:
        raise HTTPException(status_code=503, detail="ML pipeline not initialized")

    # Validate file type
    if not image.content_type or not image.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image")

    try:
        # Read image
        contents = await image.read()
        nparr = np.frombuffer(contents, np.uint8)
        img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if img is None:
            raise HTTPException(status_code=400, detail="Could not decode image")

        # Run ML pipeline
        results = pipeline.process(img)

        # Build response
        celebrities = []
        for match in results["matches"]:
            celeb_info = get_celebrity_info(match["celebrity_id"])
            brief = None
            if celeb_info:
                # Create a brief summary
                brief = f"{', '.join(celeb_info.profession[:2])}" if celeb_info.profession else None

            celebrities.append(CelebrityMatch(
                id=match["celebrity_id"],
                name=match["name"],
                confidence=match["confidence"],
                color=match["color"],
                bounding_box=BoundingBox(
                    x=match["bbox"]["x"],
                    y=match["bbox"]["y"],
                    width=match["bbox"]["width"],
                    height=match["bbox"]["height"]
                ),
                brief=brief
            ))

        # Encode annotated image as base64 PNG
        _, buffer = cv2.imencode('.png', results["annotated_image"])
        img_base64 = base64.b64encode(buffer).decode('utf-8')

        return RecognitionResponse(
            annotated_image=img_base64,
            celebrities=celebrities
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Processing error: {str(e)}")


@app.get("/celebrity/{celebrity_id}", response_model=CelebrityDetails)
async def get_celebrity_details(celebrity_id: str):
    """
    Get detailed information about a specific celebrity.

    **Path Parameters:**
    - `celebrity_id`: Unique identifier for the celebrity

    **Response:** Full celebrity details including biography, filmography, discography, etc.
    """
    info = get_celebrity_info(celebrity_id)
    if not info:
        raise HTTPException(status_code=404, detail="Celebrity not found")
    return info


@app.get("/celebrities", response_model=list[CelebrityDetails])
async def list_all_celebrities():
    """List all celebrities in the database."""
    return list_celebrities()


@app.post("/celebrity", response_model=CelebrityDetails)
async def create_celebrity(celebrity: CelebrityDetails):
    """Add a new celebrity to the database (admin endpoint)."""
    try:
        add_celebrity(
            celebrity_id=celebrity.id,
            name=celebrity.name,
            date_of_birth=celebrity.date_of_birth,
            birthplace=celebrity.birthplace,
            profession=celebrity.profession,
            biography=celebrity.biography,
            movies=[m.model_dump() for m in celebrity.movies],
            music=[m.model_dump() for m in celebrity.music],
            awards=celebrity.awards,
            image_url=celebrity.image_url
        )
        return celebrity
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
