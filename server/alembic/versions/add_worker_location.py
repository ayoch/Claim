"""add worker location

Revision ID: worker_location_001
Revises: perf_indexes_001
Create Date: 2026-03-04

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'worker_location_001'
down_revision = 'perf_indexes_001'
branch_labels = None
depends_on = None


def upgrade():
    # Add location_colony_id column (nullable initially for existing data)
    op.add_column('workers', sa.Column('location_colony_id', sa.Integer(), nullable=True))

    # Set all existing workers to Earth (colony_id=1)
    op.execute("UPDATE workers SET location_colony_id = 1 WHERE location_colony_id IS NULL")

    # Make column NOT NULL and add foreign key
    op.alter_column('workers', 'location_colony_id', nullable=False)
    op.create_foreign_key('fk_workers_location_colony', 'workers', 'colonies', ['location_colony_id'], ['id'], ondelete='CASCADE')

    # Add index for location-based queries
    op.create_index('idx_worker_location', 'workers', ['location_colony_id'])


def downgrade():
    op.drop_index('idx_worker_location', table_name='workers')
    op.drop_constraint('fk_workers_location_colony', 'workers', type_='foreignkey')
    op.drop_column('workers', 'location_colony_id')
