"""add trade missions table

Revision ID: h4i5j6k7l8m9
Revises: g3h4i5j6k7l8
Create Date: 2026-03-04

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision = 'h4i5j6k7l8m9'
down_revision = 'g3h4i5j6k7l8'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'trade_missions',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('player_id', sa.Integer(), nullable=False),
        sa.Column('ship_id', sa.Integer(), nullable=False),
        sa.Column('colony_id', sa.Integer(), nullable=True),
        sa.Column('status', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('transit_time', sa.Float(), nullable=False),
        sa.Column('elapsed_ticks', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('fuel_per_tick', sa.Float(), nullable=False),
        sa.Column('cargo', postgresql.JSONB(), nullable=False, server_default='{}'),
        sa.Column('revenue', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('origin_x', sa.Float(), nullable=False),
        sa.Column('origin_y', sa.Float(), nullable=False),
        sa.Column('origin_name', sa.String(64), nullable=False, server_default='Earth'),
        sa.Column('origin_is_earth', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('destination_x', sa.Float(), nullable=False),
        sa.Column('destination_y', sa.Float(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['player_id'], ['players.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['ship_id'], ['ships.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['colony_id'], ['colonies.id'], ondelete='SET NULL'),
    )
    op.create_index('ix_trade_missions_id', 'trade_missions', ['id'])
    op.create_index('ix_trade_missions_player_id', 'trade_missions', ['player_id'])


def downgrade() -> None:
    op.drop_index('ix_trade_missions_player_id', 'trade_missions')
    op.drop_index('ix_trade_missions_id', 'trade_missions')
    op.drop_table('trade_missions')
