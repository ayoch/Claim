"""Blog API endpoints."""
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from server.auth import require_admin_key
from server.blog_database import get_blog_db
from server.models.blog import BlogPost
from server.schemas.blog import (
    BlogPostCreate,
    BlogPostUpdate,
    BlogPostResponse,
    BlogPostListItem,
)

router = APIRouter(prefix="/api/blog", tags=["blog"])
admin_router = APIRouter(
    prefix="/api/admin/blog",
    tags=["blog-admin"],
    dependencies=[Depends(require_admin_key)]
)


# Public endpoints
@router.get("/posts", response_model=list[BlogPostListItem])
async def list_published_posts(
    limit: int = 20,
    offset: int = 0,
    db: AsyncSession = Depends(get_blog_db)
):
    """List published blog posts (newest first)."""
    result = await db.execute(
        select(BlogPost)
        .where(BlogPost.is_published == True)
        .order_by(BlogPost.published_at.desc())
        .limit(limit)
        .offset(offset)
    )
    posts = result.scalars().all()
    return posts


@router.get("/post/{slug}", response_model=BlogPostResponse)
async def get_post_by_slug(slug: str, db: AsyncSession = Depends(get_blog_db)):
    """Get a single published blog post by slug."""
    result = await db.execute(
        select(BlogPost).where(
            BlogPost.slug == slug,
            BlogPost.is_published == True
        )
    )
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    return post


# Admin endpoints
@admin_router.get("/posts", response_model=list[BlogPostListItem])
async def list_all_posts(
    limit: int = 50,
    offset: int = 0,
    db: AsyncSession = Depends(get_blog_db)
):
    """List all blog posts (including unpublished)."""
    result = await db.execute(
        select(BlogPost)
        .order_by(BlogPost.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    posts = result.scalars().all()
    return posts


@admin_router.get("/post/{post_id}", response_model=BlogPostResponse)
async def get_post_by_id(post_id: int, db: AsyncSession = Depends(get_blog_db)):
    """Get a blog post by ID (admin only)."""
    result = await db.execute(select(BlogPost).where(BlogPost.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    return post


@admin_router.post("/post", response_model=BlogPostResponse, status_code=201)
async def create_post(
    post_data: BlogPostCreate,
    db: AsyncSession = Depends(get_blog_db)
):
    """Create a new blog post."""
    # Check for duplicate slug
    result = await db.execute(select(BlogPost).where(BlogPost.slug == post_data.slug))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Slug already exists")

    post = BlogPost(
        title=post_data.title,
        slug=post_data.slug,
        content=post_data.content,
        excerpt=post_data.excerpt,
        is_published=post_data.is_published,
        published_at=datetime.now(timezone.utc) if post_data.is_published else None
    )
    db.add(post)
    await db.commit()
    await db.refresh(post)
    return post


@admin_router.patch("/post/{post_id}", response_model=BlogPostResponse)
async def update_post(
    post_id: int,
    post_data: BlogPostUpdate,
    db: AsyncSession = Depends(get_blog_db)
):
    """Update a blog post."""
    result = await db.execute(select(BlogPost).where(BlogPost.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    # Check for duplicate slug if changing slug
    if post_data.slug and post_data.slug != post.slug:
        result = await db.execute(select(BlogPost).where(BlogPost.slug == post_data.slug))
        if result.scalar_one_or_none():
            raise HTTPException(status_code=400, detail="Slug already exists")

    # Update fields
    update_data = post_data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(post, field, value)

    # Set published_at when publishing
    if post_data.is_published and not post.published_at:
        post.published_at = datetime.now(timezone.utc)
    elif post_data.is_published is False:
        post.published_at = None

    await db.commit()
    await db.refresh(post)
    return post


@admin_router.delete("/post/{post_id}", status_code=204)
async def delete_post(post_id: int, db: AsyncSession = Depends(get_blog_db)):
    """Delete a blog post."""
    result = await db.execute(select(BlogPost).where(BlogPost.id == post_id))
    post = result.scalar_one_or_none()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    await db.delete(post)
    await db.commit()
    return None
