from fastapi import FastAPI

from app_context import AppContext

from .check_routes import create_check_router
from .generate_routes import create_generate_router
from .health_pages import create_health_router


def register_routes(app: FastAPI, ctx: AppContext) -> None:
    app.include_router(create_health_router(ctx))
    app.include_router(create_check_router(ctx))
    app.include_router(create_generate_router(ctx))
