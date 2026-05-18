from datetime import datetime, date
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.repositories.tasks_repository import (
    get_tasks,
    create_task,
    get_task,
    complete_task,
    reopen_task,
    delete_task,
    update_task,
)


router = APIRouter(prefix="/tasks", tags=["tasks"])


class CreateTaskRequest(BaseModel):
    title: str
    description: Optional[str] = None
    assigned_to: Optional[str] = None
    due_date: Optional[date] = None
    priority: Optional[str] = "normal"


@router.get("")
def list_tasks(include_completed: bool = False):
    return {"tasks": get_tasks(include_completed=include_completed)}


@router.post("")
def add_task(request: CreateTaskRequest):
    if not request.title.strip():
        raise HTTPException(status_code=400, detail="Task title is required")

    return create_task(
        title=request.title.strip(),
        description=request.description,
        assigned_to=request.assigned_to,
        due_date=request.due_date,
        priority=request.priority or "normal",
        source="manual",
    )


@router.get("/{task_id}")
def read_task(task_id: UUID):
    task = get_task(task_id)

    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    return task


@router.post("/{task_id}/complete")
def mark_complete(task_id: UUID):
    task = complete_task(task_id)

    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    return task


@router.post("/{task_id}/reopen")
def mark_reopen(task_id: UUID):
    task = reopen_task(task_id)

    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    return task


@router.delete("/{task_id}")
def remove_task(task_id: UUID):
    existing = get_task(task_id)

    if not existing:
        raise HTTPException(status_code=404, detail="Task not found")

    return delete_task(task_id)

class UpdateTaskRequest(BaseModel):
    title: Optional[str] = None
    description: Optional[str] = None
    assigned_to: Optional[str] = None
    due_date: Optional[date] = None
    priority: Optional[str] = None
    status: Optional[str] = None


@router.put("/{task_id}")
def edit_task(task_id: UUID, request: UpdateTaskRequest):
    existing = get_task(task_id)

    if not existing:
        raise HTTPException(status_code=404, detail="Task not found")

    return update_task(
        task_id=task_id,
        title=request.title.strip() if request.title else None,
        description=request.description,
        assigned_to=request.assigned_to,
        due_date=request.due_date,
        priority=request.priority,
        status=request.status,
    )