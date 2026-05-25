from fastapi import APIRouter

import task_pool
from app_context import AppContext
from check_service import check_task_logic
from models import CheckTaskRequest, CheckTaskResponse


def create_check_router(ctx: AppContext) -> APIRouter:
    router = APIRouter(tags=["check"])

    @router.post("/check_task", response_model=CheckTaskResponse)
    def check_task(req: CheckTaskRequest):
        with task_pool.check_in_progress():
            return check_task_logic(
                req=req,
                ollama_base_url=ctx.settings.ollama_base_url,
                ollama_model=ctx.settings.ollama_model,
                ollama_num_predict=ctx.settings.ollama_num_predict,
                ollama_check_base_url=ctx.settings.ollama_check_base_url,
                ollama_check_model=ctx.settings.ollama_check_model,
                ollama_check_num_predict=ctx.settings.ollama_check_num_predict,
                ollama_check_timeout=ctx.settings.ollama_check_timeout,
                ollama_check_num_ctx=ctx.settings.ollama_check_num_ctx,
            )

    return router
