from fastapi import APIRouter

from app_context import AppContext
from check_service import check_task_logic
from models import CheckTaskRequest, CheckTaskResponse


def create_check_router(ctx: AppContext) -> APIRouter:
    router = APIRouter(tags=["check"])

    @router.post("/check_task", response_model=CheckTaskResponse)
    def check_task(req: CheckTaskRequest):
        return check_task_logic(
            req=req,
            ollama_base_url=ctx.settings.ollama_base_url,
            ollama_model=ctx.settings.ollama_model,
            ollama_num_predict=ctx.settings.ollama_num_predict,
        )

    return router
