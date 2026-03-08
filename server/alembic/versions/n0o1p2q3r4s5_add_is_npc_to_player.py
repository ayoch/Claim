"""add is_npc to players

Revision ID: n0o1p2q3r4s5
Revises: k7l8m9n0o1p2
Create Date: 2026-03-07

"""
from alembic import op
import sqlalchemy as sa

revision = 'n0o1p2q3r4s5'
down_revision = 'k7l8m9n0o1p2'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('players',
        sa.Column('is_npc', sa.Boolean(), nullable=False, server_default='false')
    )


def downgrade() -> None:
    op.drop_column('players', 'is_npc')
