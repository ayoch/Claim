"""Pydantic schemas for blog endpoints."""
from datetime import datetime
from pydantic import BaseModel, Field


class BlogPostCreate(BaseModel):
    """Schema for creating a blog post."""
    title: str = Field(..., min_length=1, max_length=200)
    slug: str = Field(..., min_length=1, max_length=200, pattern=r"^[a-z0-9-]+$")
    content: str = Field(..., min_length=1)
    excerpt: str = Field(default="", max_length=500)
    is_published: bool = False


class BlogPostUpdate(BaseModel):
    """Schema for updating a blog post."""
    title: str | None = Field(None, min_length=1, max_length=200)
    slug: str | None = Field(None, min_length=1, max_length=200, pattern=r"^[a-z0-9-]+$")
    content: str | None = Field(None, min_length=1)
    excerpt: str | None = Field(None, max_length=500)
    is_published: bool | None = None


class BlogPostResponse(BaseModel):
    """Schema for blog post response."""
    id: int
    title: str
    slug: str
    content: str
    excerpt: str
    is_published: bool
    created_at: datetime
    updated_at: datetime
    published_at: datetime | None

    model_config = {"from_attributes": True}


class BlogPostListItem(BaseModel):
    """Schema for blog post in list view (no full content)."""
    id: int
    title: str
    slug: str
    excerpt: str
    is_published: bool
    created_at: datetime
    published_at: datetime | None

    model_config = {"from_attributes": True}
