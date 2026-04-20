from pydantic import BaseModel
from typing import List, Optional


class CheckTaskRequest(BaseModel):
    description: str
    expected_output: Optional[str] = None
    user_code: str
    required_patterns: Optional[str] = None
    allow_direct_print: int = 0
    level: int = 1


class CheckTaskResponse(BaseModel):
    success: bool
    feedback: str
    stdout: str = ""
    stderr: str = ""


class TaskSpec(BaseModel):
    level: int
    category: str
    description: str
    expected_output: str
    required_patterns: str
    check_type: str = "stdout_exact"
    required_keywords: str = ""
    allow_direct_print: int = 0


class GenerateTasksRequest(BaseModel):
    level: int
    count: int = 5


class GenerateTasksResponse(BaseModel):
    tasks: List[TaskSpec]
    source: str = ""


class GenerateTasksMultiRequest(BaseModel):
    """Один запрос к Ollama на все уровни (быстрее, чем 4× /generate_tasks)."""

    levels: List[int] = [0, 1, 2, 3]
    count_per_level: int = 5
