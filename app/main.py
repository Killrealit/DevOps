import os
import secrets
import string
from contextlib import asynccontextmanager

import redis.asyncio as redis
from fastapi import FastAPI, HTTPException, Depends
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, HttpUrl
from prometheus_client import Counter
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import Column, Integer, String, select, text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import declarative_base

DB_USER = os.getenv("POSTGRES_USER", "shortener_user")
DB_PASS = os.getenv("POSTGRES_PASSWORD", "changeme")
DB_HOST = os.getenv("POSTGRES_HOST", "localhost")
DB_PORT = os.getenv("POSTGRES_PORT", "5432")
DB_NAME = os.getenv("POSTGRES_DB", "shortener")

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
BASE_URL = os.getenv("BASE_URL", "http://localhost:8000")

DATABASE_URL = f"postgresql+asyncpg://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

engine = create_async_engine(DATABASE_URL, echo=False)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)
Base = declarative_base()

redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

URLS_CREATED = Counter("shortener_urls_created_total", "Total number of shortened URLs created")
URLS_REDIRECTED = Counter("shortener_urls_redirected_total", "Total number of redirects", ["cache_hit"])


class URLItem(Base):
    __tablename__ = "urls"

    id = Column(Integer, primary_key=True, index=True)
    short_code = Column(String(16), unique=True, index=True, nullable=False)
    original_url = Column(String, nullable=False)


class URLCreate(BaseModel):
    url: HttpUrl


class URLResponse(BaseModel):
    short_code: str
    short_url: str
    original_url: str


@asynccontextmanager
async def lifespan(app: FastAPI):
    if os.getenv("SKIP_DB_INIT") != "true":
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
    yield
    await redis_client.aclose()
    await engine.dispose()


app = FastAPI(title="URL Shortener", version="1.0.0", lifespan=lifespan)
Instrumentator().instrument(app).expose(app)


async def get_db():
    async with AsyncSessionLocal() as session:
        yield session


def generate_short_code(length: int = 6) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


@app.get("/health", tags=["Health"])
async def health_check():
    return {"status": "ok"}


@app.get("/ready", tags=["Health"])
async def readiness_check(db: AsyncSession = Depends(get_db)):
    try:
        await db.execute(text("SELECT 1"))
        await redis_client.ping()
        return {"status": "ready"}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"Dependency unavailable: {exc}")


@app.post("/shorten", response_model=URLResponse, tags=["URLs"])
async def create_short_url(payload: URLCreate, db: AsyncSession = Depends(get_db)):
    short_code = generate_short_code()
    original_url_str = str(payload.url)

    new_url = URLItem(short_code=short_code, original_url=original_url_str)
    db.add(new_url)
    await db.commit()

    await redis_client.setex(f"url:{short_code}", 86400, original_url_str)
    URLS_CREATED.inc()

    return URLResponse(
        short_code=short_code,
        short_url=f"{BASE_URL}/{short_code}",
        original_url=original_url_str,
    )


@app.get("/{short_code}", tags=["URLs"])
async def redirect_to_url(short_code: str, db: AsyncSession = Depends(get_db)):
    cached_url = await redis_client.get(f"url:{short_code}")
    if cached_url:
        URLS_REDIRECTED.labels(cache_hit="true").inc()
        return RedirectResponse(url=cached_url, status_code=307)

    result = await db.execute(select(URLItem).where(URLItem.short_code == short_code))
    url_item = result.scalar_one_or_none()

    if not url_item:
        raise HTTPException(status_code=404, detail="Short URL not found")

    await redis_client.setex(f"url:{short_code}", 86400, url_item.original_url)
    URLS_REDIRECTED.labels(cache_hit="false").inc()

    return RedirectResponse(url=url_item.original_url, status_code=307)
