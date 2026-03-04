"""add equipment table

Revision ID: g3h4i5j6k7l8
Revises: f2g3h4i5j6k7
Create Date: 2026-03-04

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'g3h4i5j6k7l8'
down_revision = 'f2g3h4i5j6k7'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'equipment',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('ship_id', sa.Integer(), nullable=False),
        sa.Column('equipment_name', sa.String(64), nullable=False),
        sa.Column('equipment_type', sa.String(32), nullable=False),
        sa.Column('mining_bonus', sa.Float(), nullable=False, server_default='1.0'),
        sa.Column('cost', sa.Integer(), nullable=False),
        sa.Column('durability', sa.Float(), nullable=False, server_default='100.0'),
        sa.Column('max_durability', sa.Float(), nullable=False, server_default='100.0'),
        sa.Column('weapon_power', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('weapon_range', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('weapon_accuracy', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('weapon_role', sa.String(16), nullable=False, server_default=''),
        sa.Column('ammo_capacity', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('current_ammo', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('ammo_cost', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('mass', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('mining_speed_bonus', sa.Float(), nullable=False, server_default='0.0'),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['ship_id'], ['ships.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_equipment_id', 'equipment', ['id'])
    op.create_index('ix_equipment_ship_id', 'equipment', ['ship_id'])


def downgrade() -> None:
    op.drop_index('ix_equipment_ship_id', 'equipment')
    op.drop_index('ix_equipment_id', 'equipment')
    op.drop_table('equipment')
