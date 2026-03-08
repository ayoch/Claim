"""Add market_events table.

Revision ID: t6u7v8w9x0y1
Revises: s5t6u7v8w9x0
Create Date: 2026-03-08
"""
from alembic import op
import sqlalchemy as sa

revision = 't6u7v8w9x0y1'
down_revision = 's5t6u7v8w9x0'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'market_events',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('ore_type', sa.String(32), nullable=False, index=True),
        sa.Column('multiplier', sa.Float(), nullable=False),
        sa.Column('start_tick', sa.Float(), nullable=False),
        sa.Column('duration_ticks', sa.Float(), nullable=False),
        sa.Column('headline', sa.String(256), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
    )


def downgrade() -> None:
    op.drop_table('market_events')
