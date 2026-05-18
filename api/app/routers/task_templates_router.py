from datetime import date
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.repositories.task_templates_repository import (
    get_task_templates,
    create_task_template,
    get_task_template,
    generate_recurring_tasks,
)


router = APIRouter(prefix="/task-templates", tags=["task-templates"])


class CreateTaskTemplateRequest(BaseModel):
    title: str
    description: Optional[str] = None
    assigned_to: Optional[str] = None
    recurrence_type: str = "weekly"
    day_of_week: Optional[int] = None
    day_of_month: Optional[int] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    expires_after_days: Optional[int] = None
    priority: Optional[str] = "normal"
    visible_day_offset: Optional[int] = 0
    visible_time: Optional[str] = None
    due_day_offset: Optional[int] = 0
    due_time: Optional[str] = None


@router.get("")
def list_task_templates(active_only: bool = True):
    return {"templates": get_task_templates(active_only=active_only)}


@router.post("")
def add_task_template(request: CreateTaskTemplateRequest):
    if not request.title.strip():
        raise HTTPException(status_code=400, detail="Template title is required")

    if request.recurrence_type not in ["weekly", "fortnightly", "monthly"]:
        raise HTTPException(status_code=400, detail="Invalid recurrence_type")

    if request.recurrence_type in ["weekly", "fortnightly"] and request.day_of_week is None:
        raise HTTPException(status_code=400, detail="day_of_week is required")

    if request.recurrence_type == "monthly" and request.day_of_month is None:
        raise HTTPException(status_code=400, detail="day_of_month is required")

    return create_task_template(
        title=request.title.strip(),
        description=request.description,
        assigned_to=request.assigned_to,
        recurrence_type=request.recurrence_type,
        day_of_week=request.day_of_week,
        day_of_month=request.day_of_month,
        start_date=request.start_date,
        end_date=request.end_date,
        expires_after_days=request.expires_after_days,
        priority=request.priority or "normal",

        visible_day_offset=request.visible_day_offset,
        visible_time=request.visible_time,
        due_day_offset=request.due_day_offset,
        due_time=request.due_time,
    )


@router.get("/{template_id}")
def read_task_template(template_id: UUID):
    template = get_task_template(template_id)

    if not template:
        raise HTTPException(status_code=404, detail="Template not found")

    return template


@router.post("/generate")
def generate(days_ahead: int = 21):
    return generate_recurring_tasks(days_ahead=days_ahead)