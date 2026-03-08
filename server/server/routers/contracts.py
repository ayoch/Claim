"""Contract API — list, accept, and query delivery contracts."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from server.database import get_db
from server.models.contract import (
    Contract,
    STATUS_AVAILABLE, STATUS_ACCEPTED, STATUS_COMPLETED, STATUS_FAILED,
)
from server.models.player import Player
from server.routers.auth import get_current_player
from server.schemas.game import ContractOut

router = APIRouter(prefix="/game/contracts", tags=["contracts"])


@router.get("", response_model=list[ContractOut])
async def list_contracts(
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    """Return all available contracts plus this player's active/completed ones."""
    result = await db.execute(
        select(Contract).where(
            (Contract.status == STATUS_AVAILABLE) |
            (Contract.player_id == player.id)
        )
    )
    return list(result.scalars().all())


@router.post("/{contract_id}/accept", response_model=ContractOut)
async def accept_contract(
    contract_id: int,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    """Accept an available contract."""
    result = await db.execute(select(Contract).where(Contract.id == contract_id))
    contract = result.scalar_one_or_none()
    if not contract:
        raise HTTPException(status_code=404, detail="Contract not found")
    if not contract.can_accept(player.id):
        raise HTTPException(status_code=409, detail="Contract not available")

    contract.status = STATUS_ACCEPTED
    contract.player_id = player.id
    contract.original_deadline_ticks = contract.deadline_ticks
    db.add(contract)
    await db.commit()
    await db.refresh(contract)
    return contract
