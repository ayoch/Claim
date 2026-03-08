"""Add contracts table

Revision ID: q3r4s5t6u7v8
Revises: p2q3r4s5t6u7
Create Date: 2026-03-07

"""
from alembic import op
import sqlalchemy as sa

revision = 'q3r4s5t6u7v8'
down_revision = 'p2q3r4s5t6u7'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'contracts',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('player_id', sa.Integer(), sa.ForeignKey('players.id', ondelete='CASCADE'), nullable=True, index=True),
        sa.Column('ore_type', sa.String(32), nullable=False),
        sa.Column('quantity', sa.Float(), nullable=False),
        sa.Column('quantity_delivered', sa.Float(), nullable=False, server_default='0'),
        sa.Column('reward', sa.Integer(), nullable=False),
        sa.Column('deadline_ticks', sa.Float(), nullable=False),
        sa.Column('original_deadline_ticks', sa.Float(), nullable=False, server_default='0'),
        sa.Column('status', sa.Integer(), nullable=False, server_default='0', index=True),
        sa.Column('issuer_name', sa.String(128), nullable=False),
        sa.Column('delivery_colony_id', sa.Integer(), sa.ForeignKey('colonies.id', ondelete='SET NULL'), nullable=True),
        sa.Column('allows_partial', sa.Boolean(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('accepted_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_contracts_id', 'contracts', ['id'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_contracts_id', table_name='contracts')
    op.drop_table('contracts')
