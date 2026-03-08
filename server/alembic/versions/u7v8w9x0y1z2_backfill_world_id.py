"""Backfill world_id = 1 on world_state rows where world_id is NULL.

The multi_world_prep migration added world_id but its backfill was skipped
on production because the guarded EXISTS check evaluated false. This causes
load_world_state() to find no row matching world_id=1, creating a fresh
world state at tick 0 and resetting the game date.

Revision ID: u7v8w9x0y1z2
Revises: t6u7v8w9x0y1
Create Date: 2026-03-08
"""
from alembic import op

revision = 'u7v8w9x0y1z2'
down_revision = 't6u7v8w9x0y1'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("""
        UPDATE world_state
        SET world_id = 1
        WHERE world_id IS NULL
    """)


def downgrade() -> None:
    pass
