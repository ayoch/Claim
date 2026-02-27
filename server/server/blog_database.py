"""Blog/Website database (SQLite) - separate from game database."""
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from server.config import settings

# Blog database engine (SQLite)
blog_engine = create_async_engine(
    settings.BLOG_DATABASE_URL,
    echo=False,
    future=True,
)

BlogSessionLocal = async_sessionmaker(
    blog_engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class BlogBase(DeclarativeBase):
    """Base class for blog models."""
    pass


async def init_blog_db():
    """Create blog database tables (if they don't exist)."""
    async with blog_engine.begin() as conn:
        await conn.run_sync(BlogBase.metadata.create_all)


async def get_blog_db():
    """Dependency for blog database sessions."""
    async with BlogSessionLocal() as session:
        yield session
