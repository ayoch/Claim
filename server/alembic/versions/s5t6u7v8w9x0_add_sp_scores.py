"""Add sp_scores table for global single-player leaderboard.

Revision ID: s5t6u7v8w9x0
Revises: r4s5t6u7v8w9
Create Date: 2026-03-08
"""
from alembic import op
import sqlalchemy as sa

revision = 's5t6u7v8w9x0'
down_revision = 'r4s5t6u7v8w9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'sp_scores',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('player_name', sa.String(64), nullable=False, index=True),
        sa.Column('net_worth', sa.Integer(), nullable=False),
        sa.Column('ships_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('workers_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('game_date', sa.String(64), nullable=False, server_default=''),
        sa.Column('submitted_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()')),
    )


def downgrade() -> None:
    op.drop_table('sp_scores')
