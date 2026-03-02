"""add_email_and_password_reset

Revision ID: b1c2d3e4f5a6
Revises: a1b2c3d4e5f6
Create Date: 2026-03-02 11:00:00.000000

"""
from __future__ import annotations
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b1c2d3e4f5a6'
down_revision: Union[str, None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    from sqlalchemy import inspect
    from alembic import op

    conn = op.get_bind()
    inspector = inspect(conn)

    # Add email column to players table if it doesn't exist
    columns = [col['name'] for col in inspector.get_columns('players')]
    if 'email' not in columns:
        op.add_column('players', sa.Column('email', sa.String(255), nullable=True, unique=True, index=True))

    # Create password_reset_tokens table if it doesn't exist
    if 'password_reset_tokens' not in inspector.get_table_names():
        op.create_table(
            'password_reset_tokens',
            sa.Column('id', sa.Integer(), primary_key=True, index=True),
            sa.Column('player_id', sa.Integer(), sa.ForeignKey('players.id', ondelete='CASCADE'), nullable=False, index=True),
            sa.Column('token', sa.String(255), unique=True, nullable=False, index=True),
            sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
            sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
            sa.Column('used_at', sa.DateTime(timezone=True), nullable=True),
        )


def downgrade() -> None:
    op.drop_table('password_reset_tokens')
    op.drop_column('players', 'email')
