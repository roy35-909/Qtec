from fastapi import FastAPI
from pydantic import BaseModel
import logging, time

app = FastAPI()
logging.basicConfig(level=logging.INFO)

class DataPayload(BaseModel):
    key: str
    value: str

@app.get("/status")
def status():
    return {"status": "ok", "timestamp": time.time()}

@app.post("/data")
def receive_data(payload: DataPayload):
    logging.info(f"Received: {payload}")
    return {"received": True, "key": payload.key}