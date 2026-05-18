from typing import Optional
from uuid import UUID

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.repositories.lists_repository import (
    get_lists,
    create_list,
    get_list,
    add_list_item,
    complete_list_item,
    delete_list_item,
)


router = APIRouter(prefix="/lists", tags=["lists"])


class CreateListRequest(BaseModel):
    name: str
    list_type: Optional[str] = "general"
    is_primary: Optional[bool] = False


class AddListItemRequest(BaseModel):
    text: str
    quantity: Optional[str] = None
    notes: Optional[str] = None


@router.get("")
def list_household_lists():
    return {"lists": get_lists()}


@router.post("")
def add_household_list(request: CreateListRequest):
    if not request.name.strip():
        raise HTTPException(status_code=400, detail="List name is required")

    return create_list(
        name=request.name.strip(),
        list_type=request.list_type or "general",
        is_primary=request.is_primary or False,
    )


@router.get("/{list_id}")
def read_household_list(list_id: UUID):
    household_list = get_list(list_id)

    if not household_list:
        raise HTTPException(status_code=404, detail="List not found")

    return household_list


@router.post("/{list_id}/items")
def add_item(list_id: UUID, request: AddListItemRequest):
    household_list = get_list(list_id)

    if not household_list:
        raise HTTPException(status_code=404, detail="List not found")

    if not request.text.strip():
        raise HTTPException(status_code=400, detail="Item text is required")

    return add_list_item(
        list_id=list_id,
        text=request.text.strip(),
        quantity=request.quantity,
        notes=request.notes,
    )


@router.post("/items/{item_id}/complete")
def complete_item(item_id: UUID):
    return complete_list_item(item_id)


@router.delete("/items/{item_id}")
def delete_item(item_id: UUID):
    return delete_list_item(item_id)