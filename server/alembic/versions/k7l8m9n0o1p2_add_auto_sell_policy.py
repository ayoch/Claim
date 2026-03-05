"""add auto_sell_on_return policy to players

Revision ID: k7l8m9n0o1p2
Revises: perf_indexes_001
Create Date: 2026-03-04

"""
from alembic import op
import sqlalchemy as sa

revision = 'k7l8m9n0o1p2'
down_revision = 'worker_location_001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('players',
        sa.Column('auto_sell_on_return', sa.Boolean(), nullable=False, server_default='true')
    )


def downgrade() -> None:
    op.drop_column('players', 'auto_sell_on_return')
