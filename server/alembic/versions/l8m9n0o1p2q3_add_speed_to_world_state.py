"""add speed_multiplier to world_state

Revision ID: l8m9n0o1p2q3
Revises: k7l8m9n0o1p2
Create Date: 2026-03-07

"""
from alembic import op
import sqlalchemy as sa

revision = 'l8m9n0o1p2q3'
down_revision = 'k7l8m9n0o1p2'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('world_state',
        sa.Column('speed_multiplier', sa.Float(), nullable=False, server_default='1.0')
    )


def downgrade() -> None:
    op.drop_column('world_state', 'speed_multiplier')
