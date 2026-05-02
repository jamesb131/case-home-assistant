from fastapi import FastAPI
from app.services.sigenergy_client import get_energy_snapshot

app = FastAPI()

@app.get("/")
def root():
    return {"message": "CASE is online"}

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/energy/current")
def energy_current():
    return get_energy_snapshot()