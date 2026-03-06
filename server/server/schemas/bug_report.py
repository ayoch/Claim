from datetime import datetime
from pydantic import BaseModel, Field


class BugReportCreate(BaseModel):
    """Request schema for creating a bug report"""
    title: str = Field(..., min_length=10, max_length=200)
    description: str = Field(..., min_length=20, max_length=5000)
    category: str = Field(default="general", max_length=50)
    game_version: str = Field(default="0.1.0", max_length=20)
    backend_mode: str = Field(..., pattern="^(local|server)$")
    reporter_username: str = Field(default="Anonymous", max_length=32)


class BugReportOut(BaseModel):
    """Response schema for bug reports"""
    id: int
    player_id: int | None
    reporter_username: str
    title: str
    description: str
    category: str
    status: str
    game_version: str
    backend_mode: str
    created_at: datetime
    updated_at: datetime
    admin_notes: str | None

    model_config = {"from_attributes": True}


class BugReportUpdate(BaseModel):
    """Schema for updating bug report status"""
    status: str | None = Field(None, pattern="^(open|in_progress|done|wont_fix|duplicate)$")
    admin_notes: str | None = Field(None, max_length=2000)


class BugReportListResponse(BaseModel):
    """Response schema for list endpoint"""
    total: int
    reports: list[BugReportOut]
