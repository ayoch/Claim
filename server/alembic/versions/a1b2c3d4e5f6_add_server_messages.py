"""add_server_messages

Revision ID: a1b2c3d4e5f6
Revises: 2a20b17739f3
Create Date: 2026-02-28 00:00:00.000000

"""
from __future__ import annotations
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = '2a20b17739f3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'server_messages',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('message', sa.String(500), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table('server_messages')
