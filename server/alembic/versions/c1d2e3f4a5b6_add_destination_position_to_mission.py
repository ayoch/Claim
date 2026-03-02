"""add_destination_position_to_mission

Revision ID: c1d2e3f4a5b6
Revises: b1c2d3e4f5a6
Create Date: 2026-03-02 12:00:00.000000

"""
from __future__ import annotations
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'c1d2e3f4a5b6'
down_revision: Union[str, None] = 'b1c2d3e4f5a6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    from sqlalchemy import inspect

    conn = op.get_bind()
    inspector = inspect(conn)

    # Add destination position fields to missions table if they don't exist
    columns = [col['name'] for col in inspector.get_columns('missions')]
    if 'destination_x' not in columns:
        op.add_column('missions', sa.Column('destination_x', sa.Float(), server_default='0.0', nullable=False))
    if 'destination_y' not in columns:
        op.add_column('missions', sa.Column('destination_y', sa.Float(), server_default='0.0', nullable=False))


def downgrade() -> None:
    op.drop_column('missions', 'destination_y')
    op.drop_column('missions', 'destination_x')
