import html
import re
from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import select, or_, func
from sqlalchemy.ext.asyncio import AsyncSession
from server.auth import require_admin
from server.database import get_db
from server.models.bug_report import BugReport
from server.models.player import Player
from server.schemas.bug_report import (
    BugReportCreate,
    BugReportOut,
    BugReportUpdate,
    BugReportListResponse
)
from server.rate_limit import limiter


def sanitize_text(text: str) -> str:
    """
    Sanitize user input to prevent XSS and injection attacks.

    1. HTML-escape all special characters
    2. Remove null bytes
    3. Limit consecutive whitespace
    4. Remove control characters except newlines/tabs
    """
    # Remove null bytes
    text = text.replace('\x00', '')

    # Remove control characters except newline, carriage return, and tab
    text = ''.join(char for char in text if char in '\n\r\t' or not (0 <= ord(char) < 32))

    # HTML escape to prevent XSS
    text = html.escape(text, quote=True)

    # Limit consecutive whitespace (prevent layout attacks)
    text = re.sub(r'\s{10,}', ' ' * 10, text)

    return text.strip()

router = APIRouter(prefix="/api/bug-reports", tags=["bug_reports"])


@router.post("", response_model=BugReportOut, status_code=status.HTTP_201_CREATED)
@limiter.limit("5/hour")  # Prevent spam
async def create_bug_report(
    request: Request,
    payload: BugReportCreate,
    db: AsyncSession = Depends(get_db),
):
    """Submit a bug report (no auth required, but username captured if logged in)"""

    # Sanitize all user inputs to prevent XSS and injection attacks
    sanitized_title = sanitize_text(payload.title)
    sanitized_description = sanitize_text(payload.description)
    sanitized_category = sanitize_text(payload.category)
    sanitized_username = sanitize_text(payload.reporter_username)
    sanitized_version = sanitize_text(payload.game_version)

    # Additional validation: ensure sanitized inputs still meet minimum requirements
    if len(sanitized_title) < 10:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Title must be at least 10 characters after sanitization"
        )

    if len(sanitized_description) < 20:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Description must be at least 20 characters after sanitization"
        )

    # Create bug report with sanitized data
    bug_report = BugReport(
        title=sanitized_title,
        description=sanitized_description,
        category=sanitized_category,
        game_version=sanitized_version,
        backend_mode=payload.backend_mode,  # Enum validated by Pydantic
        reporter_username=sanitized_username,
        status="open"
    )

    db.add(bug_report)
    await db.commit()
    await db.refresh(bug_report)

    return BugReportOut.model_validate(bug_report)


@router.get("", response_model=BugReportListResponse)
@limiter.limit("60/minute")
async def list_bug_reports(
    request: Request,
    player: Player = Depends(require_admin),  # Admin only
    db: AsyncSession = Depends(get_db),
    status_filter: str | None = Query(None, pattern="^(open|in_progress|done|wont_fix|duplicate)$"),
    category: str | None = Query(None, max_length=50),
    search: str | None = Query(None, max_length=200),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """List bug reports with filtering and search (admin only)"""

    # Build query
    query = select(BugReport).order_by(BugReport.created_at.desc())

    # Apply filters
    if status_filter:
        query = query.where(BugReport.status == status_filter)

    if category:
        query = query.where(BugReport.category == category)

    if search:
        # Full-text search across title and description
        search_term = f"%{search}%"
        query = query.where(
            or_(
                BugReport.title.ilike(search_term),
                BugReport.description.ilike(search_term)
            )
        )

    # Get total count
    count_query = select(func.count()).select_from(query.subquery())
    total = await db.scalar(count_query)

    # Apply pagination
    query = query.limit(limit).offset(offset)

    # Execute query
    result = await db.execute(query)
    reports = result.scalars().all()

    return BugReportListResponse(
        total=total or 0,
        reports=[BugReportOut.model_validate(r) for r in reports]
    )


@router.get("/{report_id}", response_model=BugReportOut)
@limiter.limit("60/minute")
async def get_bug_report(
    request: Request,
    report_id: int,
    player: Player = Depends(require_admin),  # Admin only
    db: AsyncSession = Depends(get_db),
):
    """Get single bug report by ID (admin only)"""

    result = await db.execute(
        select(BugReport).where(BugReport.id == report_id)
    )
    report = result.scalar_one_or_none()

    if not report:
        raise HTTPException(status_code=404, detail="Bug report not found")

    return BugReportOut.model_validate(report)


@router.patch("/{report_id}", response_model=BugReportOut)
@limiter.limit("30/minute")
async def update_bug_report(
    request: Request,
    report_id: int,
    payload: BugReportUpdate,
    player: Player = Depends(require_admin),  # Admin only
    db: AsyncSession = Depends(get_db),
):
    """Update bug report status/notes (admin only)"""

    result = await db.execute(
        select(BugReport).where(BugReport.id == report_id)
    )
    report = result.scalar_one_or_none()

    if not report:
        raise HTTPException(status_code=404, detail="Bug report not found")

    # Update fields (status is validated by Pydantic enum)
    if payload.status is not None:
        report.status = payload.status

    # Sanitize admin notes
    if payload.admin_notes is not None:
        report.admin_notes = sanitize_text(payload.admin_notes)

    await db.commit()
    await db.refresh(report)

    return BugReportOut.model_validate(report)


@router.delete("/{report_id}", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("10/hour")
async def delete_bug_report(
    request: Request,
    report_id: int,
    player: Player = Depends(require_admin),  # Admin only
    db: AsyncSession = Depends(get_db),
):
    """Delete a bug report (admin only)"""

    result = await db.execute(
        select(BugReport).where(BugReport.id == report_id)
    )
    report = result.scalar_one_or_none()

    if not report:
        raise HTTPException(status_code=404, detail="Bug report not found")

    await db.delete(report)
    await db.commit()
