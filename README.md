# Celebrity Lookup App

An iOS app that identifies celebrities in photos using deep learning, displays colored outlines around each identified person, and provides detailed information about them.

## Features

- **Celebrity Recognition**: Identify celebrities in photos using face recognition
- **Colored Edges**: Each identified celebrity gets a unique colored outline (Brooklyn Nine-Nine style)
- **Detailed Information**: View biography, filmography, discography, and awards
- **Multiple Detection**: Identify multiple celebrities in a single photo

## Architecture

```
┌─────────────────┐         ┌─────────────────────────────────────┐
│   iOS App       │  HTTP   │           Python Backend            │
│   (SwiftUI)     │◄───────►│  FastAPI + ML Models + SQLite       │
└─────────────────┘         └─────────────────────────────────────┘
```

## Quick Start

### 1. Backend Setup

```bash
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run the server
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

The first run will download the InsightFace model (~300MB) and the segmentation model.

### 2. Add Celebrity Data

#### Option A: Add images manually
1. Create folders in `backend/data/celebrity_images/`:
   ```
   celebrity_images/
       taylor_swift/
           photo1.jpg
           photo2.jpg
       tom_hanks/
           photo1.jpg
   ```

2. Run the database builder:
   ```bash
   python scripts/build_celebrity_db.py
   ```

3. Edit `backend/data/celebrity_metadata.json` with celebrity info

4. Run the builder again to populate the database

#### Option B: Use the API
```bash
# Add a celebrity via API
curl -X POST http://localhost:8000/celebrity \
  -H "Content-Type: application/json" \
  -d '{
    "id": "taylor_swift",
    "name": "Taylor Swift",
    "date_of_birth": "1989-12-13",
    "profession": ["Singer", "Songwriter"],
    "biography": "..."
  }'
```

### 3. iOS App Setup

1. Open Xcode and create a new project:
   - File > New > Project > iOS App
   - Name: CelebrityLookup
   - Interface: SwiftUI
   - Language: Swift

2. Copy the Swift files from `ios-app/CelebrityLookup/` into your Xcode project

3. Update `APIService.swift` with your backend URL:
   - For simulator: `http://localhost:8000`
   - For device: `http://<your-mac-ip>:8000`

4. Build and run on simulator or device

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Health check |
| `/recognize` | POST | Upload image, get recognized celebrities |
| `/celebrity/{id}` | GET | Get detailed celebrity info |
| `/celebrities` | GET | List all celebrities in database |
| `/stats` | GET | Get API statistics |

### Example: Recognize Celebrities

```bash
curl -X POST http://localhost:8000/recognize \
  -F "image=@photo.jpg"
```

Response:
```json
{
  "annotated_image": "<base64 PNG>",
  "celebrities": [
    {
      "id": "taylor_swift",
      "name": "Taylor Swift",
      "confidence": 0.89,
      "color": "#FF6B6B",
      "bounding_box": {"x": 100, "y": 50, "width": 200, "height": 200},
      "brief": "Singer, Songwriter"
    }
  ]
}
```

## ML Models Used

| Model | Purpose | Size |
|-------|---------|------|
| InsightFace buffalo_l | Face detection & recognition | ~300MB |
| U2-Net Human Seg | Person segmentation | ~170MB |

## Project Structure

```
celebrity-lookup/
├── backend/
│   ├── app/
│   │   ├── main.py              # FastAPI endpoints
│   │   ├── models.py            # Pydantic models
│   │   ├── database.py          # SQLite setup
│   │   ├── celebrity_db.py      # Celebrity CRUD
│   │   └── ml/
│   │       └── pipeline.py      # ML processing
│   ├── data/
│   │   ├── celebrity_images/    # Training images
│   │   ├── celebrity_encodings/ # Face vectors
│   │   └── celebrities.db       # SQLite database
│   ├── scripts/
│   │   └── build_celebrity_db.py
│   └── requirements.txt
│
└── ios-app/
    └── CelebrityLookup/
        ├── Models/
        ├── Views/
        ├── Services/
        └── Info.plist
```

## Tips

### Building a Good Celebrity Database

1. **Use 3-5 images per celebrity** for better accuracy
2. **Varied photos**: Different angles, lighting, expressions
3. **Clear face visibility**: Avoid sunglasses, heavy makeup variations
4. **Recent photos**: Use photos from similar time periods

### Performance

- First request is slow (model loading)
- Subsequent requests: ~1-3 seconds per image
- GPU acceleration available with CUDA (change provider in pipeline.py)

### Troubleshooting

**"No celebrities recognized"**
- Ensure celebrity encodings exist in `data/celebrity_encodings/`
- Check face is clearly visible in photo
- Lower the threshold in `pipeline.py` (default: 0.4)

**iOS app can't connect**
- Check backend is running on correct port
- For device testing, use Mac's IP address (not localhost)
- Ensure firewall allows connections on port 8000

## License

MIT License
