"""add rigs and stockpiles

Revision ID: i5j6k7l8m9n0
Revises: h4i5j6k7l8m9
Create Date: 2026-03-04

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'i5j6k7l8m9n0'
down_revision = 'h4i5j6k7l8m9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create rigs table
    op.create_table(
        'rigs',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('player_id', sa.Integer(), nullable=False),
        sa.Column('unit_type', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('unit_name', sa.String(64), nullable=False),
        sa.Column('mass', sa.Float(), nullable=False),
        sa.Column('workers_required', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('mining_multiplier', sa.Float(), nullable=False, server_default='1.0'),
        sa.Column('cost', sa.Integer(), nullable=False),
        sa.Column('durability', sa.Float(), nullable=False, server_default='100.0'),
        sa.Column('max_durability', sa.Float(), nullable=False, server_default='100.0'),
        sa.Column('wear_per_day', sa.Float(), nullable=False, server_default='0.3'),
        sa.Column('deployed_at_asteroid_id', sa.Integer(), nullable=True),
        sa.Column('deployed_at_tick', sa.Float(), nullable=False, server_default='0.0'),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['player_id'], ['players.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['deployed_at_asteroid_id'], ['asteroids.id'], ondelete='SET NULL'),
    )
    op.create_index('ix_rigs_id', 'rigs', ['id'])
    op.create_index('ix_rigs_player_id', 'rigs', ['player_id'])
    op.create_index('ix_rigs_deployed_at_asteroid_id', 'rigs', ['deployed_at_asteroid_id'])

    # Create stockpiles table
    op.create_table(
        'stockpiles',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('player_id', sa.Integer(), nullable=False),
        sa.Column('asteroid_id', sa.Integer(), nullable=False),
        sa.Column('ore_type', sa.String(32), nullable=False),
        sa.Column('tonnes', sa.Float(), nullable=False, server_default='0.0'),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['player_id'], ['players.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['asteroid_id'], ['asteroids.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_stockpiles_id', 'stockpiles', ['id'])
    op.create_index('ix_stockpiles_player_id', 'stockpiles', ['player_id'])
    op.create_index('ix_stockpiles_asteroid_id', 'stockpiles', ['asteroid_id'])

    # Add assigned_rig_id to workers table
    op.add_column('workers', sa.Column('assigned_rig_id', sa.Integer(), nullable=True))
    op.create_foreign_key('fk_workers_assigned_rig_id', 'workers', 'rigs', ['assigned_rig_id'], ['id'], ondelete='SET NULL')


def downgrade() -> None:
    op.drop_constraint('fk_workers_assigned_rig_id', 'workers', type_='foreignkey')
    op.drop_column('workers', 'assigned_rig_id')

    op.drop_index('ix_stockpiles_asteroid_id', 'stockpiles')
    op.drop_index('ix_stockpiles_player_id', 'stockpiles')
    op.drop_index('ix_stockpiles_id', 'stockpiles')
    op.drop_table('stockpiles')

    op.drop_index('ix_rigs_deployed_at_asteroid_id', 'rigs')
    op.drop_index('ix_rigs_player_id', 'rigs')
    op.drop_index('ix_rigs_id', 'rigs')
    op.drop_table('rigs')
