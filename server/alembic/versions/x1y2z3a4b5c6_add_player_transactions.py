"""Add player_transactions audit table.

Revision ID: x1y2z3a4b5c6
Revises: w9x0y1z2a3b4
Create Date: 2026-03-08
"""
from alembic import op
import sqlalchemy as sa

revision = 'x1y2z3a4b5c6'
down_revision = 'w9x0y1z2a3b4'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'player_transactions',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('player_id', sa.Integer(),
                  sa.ForeignKey('players.id', ondelete='CASCADE'),
                  nullable=False, index=True),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('amount', sa.BigInteger(), nullable=False),
        sa.Column('balance_after', sa.BigInteger(), nullable=False),
        sa.Column('game_ticks', sa.Float(), nullable=False, server_default='0'),
        sa.Column('source', sa.String(32), nullable=False),
        sa.Column('detail', sa.String(128), nullable=False, server_default=''),
    )


def downgrade() -> None:
    op.drop_table('player_transactions')
