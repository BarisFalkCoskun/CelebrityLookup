from typing import Optional, List
from sqlalchemy.orm import Session

from app.database import SessionLocal, Celebrity, init_db
from app.models import CelebrityDetails, MovieCredit, MusicCredit


def get_celebrity_info(celebrity_id: str) -> Optional[CelebrityDetails]:
    """Fetch celebrity details from database."""
    with SessionLocal() as session:
        celeb = session.query(Celebrity).filter(Celebrity.id == celebrity_id).first()
        if celeb:
            # Parse movies
            movies = []
            if celeb.movies:
                for m in celeb.movies:
                    movies.append(MovieCredit(
                        title=m.get("title", ""),
                        year=m.get("year", 0),
                        role=m.get("role", "")
                    ))

            # Parse music
            music = []
            if celeb.music:
                for m in celeb.music:
                    music.append(MusicCredit(
                        title=m.get("title", ""),
                        year=m.get("year", 0),
                        type=m.get("type", "")
                    ))

            return CelebrityDetails(
                id=celeb.id,
                name=celeb.name,
                date_of_birth=celeb.date_of_birth,
                birthplace=celeb.birthplace,
                profession=celeb.profession or [],
                biography=celeb.biography or "",
                movies=movies,
                music=music,
                awards=celeb.awards or [],
                image_url=celeb.image_url
            )
    return None


def add_celebrity(
    celebrity_id: str,
    name: str,
    date_of_birth: Optional[str] = None,
    birthplace: Optional[str] = None,
    profession: Optional[List[str]] = None,
    biography: Optional[str] = None,
    movies: Optional[List[dict]] = None,
    music: Optional[List[dict]] = None,
    awards: Optional[List[str]] = None,
    image_url: Optional[str] = None
) -> Celebrity:
    """Add a celebrity to the database."""
    with SessionLocal() as session:
        celeb = Celebrity(
            id=celebrity_id,
            name=name,
            date_of_birth=date_of_birth,
            birthplace=birthplace,
            profession=profession,
            biography=biography,
            movies=movies,
            music=music,
            awards=awards,
            image_url=image_url
        )
        session.add(celeb)
        session.commit()
        session.refresh(celeb)
        return celeb


def update_celebrity(celebrity_id: str, **kwargs) -> Optional[Celebrity]:
    """Update a celebrity in the database."""
    with SessionLocal() as session:
        celeb = session.query(Celebrity).filter(Celebrity.id == celebrity_id).first()
        if celeb:
            for key, value in kwargs.items():
                if hasattr(celeb, key):
                    setattr(celeb, key, value)
            session.commit()
            session.refresh(celeb)
            return celeb
    return None


def delete_celebrity(celebrity_id: str) -> bool:
    """Delete a celebrity from the database."""
    with SessionLocal() as session:
        celeb = session.query(Celebrity).filter(Celebrity.id == celebrity_id).first()
        if celeb:
            session.delete(celeb)
            session.commit()
            return True
    return False


def list_celebrities() -> List[CelebrityDetails]:
    """List all celebrities in the database."""
    celebrities = []
    with SessionLocal() as session:
        for celeb in session.query(Celebrity).all():
            celebrities.append(CelebrityDetails(
                id=celeb.id,
                name=celeb.name,
                date_of_birth=celeb.date_of_birth,
                birthplace=celeb.birthplace,
                profession=celeb.profession or [],
                biography=celeb.biography or "",
                movies=[],  # Simplified for listing
                music=[],
                awards=celeb.awards or [],
                image_url=celeb.image_url
            ))
    return celebrities
