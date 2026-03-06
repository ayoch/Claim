"""add_bug_reports_table

Revision ID: 65573384f3cc
Revises: k7l8m9n0o1p2
Create Date: 2026-03-06 11:57:09.496006

"""
from __future__ import annotations
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '65573384f3cc'
down_revision: Union[str, None] = 'k7l8m9n0o1p2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'bug_reports',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('player_id', sa.Integer(), nullable=True),
        sa.Column('reporter_username', sa.String(length=32), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('description', sa.Text(), nullable=False),
        sa.Column('category', sa.String(length=50), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False),
        sa.Column('game_version', sa.String(length=20), nullable=False),
        sa.Column('backend_mode', sa.String(length=10), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('admin_notes', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['player_id'], ['players.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_bug_reports_id', 'bug_reports', ['id'])
    op.create_index('ix_bug_reports_player_id', 'bug_reports', ['player_id'])
    op.create_index('ix_bug_reports_title', 'bug_reports', ['title'])
    op.create_index('ix_bug_reports_category', 'bug_reports', ['category'])
    op.create_index('ix_bug_reports_status', 'bug_reports', ['status'])
    op.create_index('ix_bug_reports_created_at', 'bug_reports', ['created_at'])


def downgrade() -> None:
    op.drop_index('ix_bug_reports_created_at', table_name='bug_reports')
    op.drop_index('ix_bug_reports_status', table_name='bug_reports')
    op.drop_index('ix_bug_reports_category', table_name='bug_reports')
    op.drop_index('ix_bug_reports_title', table_name='bug_reports')
    op.drop_index('ix_bug_reports_player_id', table_name='bug_reports')
    op.drop_index('ix_bug_reports_id', table_name='bug_reports')
    op.drop_table('bug_reports')
