from sqlalchemy import create_engine, Column, String, Text, JSON
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os

# Get the directory where this file is located
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(BASE_DIR, "data", "celebrities.db")

# Ensure data directory exists
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

engine = create_engine(f"sqlite:///{DB_PATH}", echo=False)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class Celebrity(Base):
    __tablename__ = "celebrities"

    id = Column(String, primary_key=True)
    name = Column(String, nullable=False)
    date_of_birth = Column(String, nullable=True)
    birthplace = Column(String, nullable=True)
    profession = Column(JSON, nullable=True)  # List of professions
    biography = Column(Text, nullable=True)
    movies = Column(JSON, nullable=True)  # List of {title, year, role}
    music = Column(JSON, nullable=True)  # List of {title, year, type}
    awards = Column(JSON, nullable=True)  # List of award strings
    image_url = Column(String, nullable=True)


def init_db():
    """Initialize the database tables."""
    Base.metadata.create_all(bind=engine)


def get_db():
    """Get database session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
