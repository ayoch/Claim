from datetime import datetime

from sqlalchemy import DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from server.database import Base


class ServerMessage(Base):
    __tablename__ = "server_messages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    message: Mapped[str] = mapped_column(String(500), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
