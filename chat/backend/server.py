import os
import json
import asyncio
import logging
from datetime import datetime
from typing import List

import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
import redis.asyncio as redis
from pydantic import BaseModel

# Configurare logging simplă
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configurare din environment
PORT = int(os.getenv('PORT', 3000))
MONGO_URL = os.getenv('MONGO_URL', 'mongodb://chat-db:27017/chatdb')
REDIS_URL = os.getenv('REDIS_URL', 'redis://redis:6379')

# Modele Pydantic
class MessageData(BaseModel):
    username: str
    text: str

# FastAPI app
app = FastAPI(title="Chat Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global variables
mongo_client = None
database = None
redis_client = None
redis_pubsub = None
active_connections: List[WebSocket] = []

@app.on_event("startup")
async def startup_event():
    global mongo_client, database, redis_client, redis_pubsub
    
    try:
        # Conectare MongoDB
        mongo_client = AsyncIOMotorClient(MONGO_URL, serverSelectionTimeoutMS=3000)
        await mongo_client.admin.command('ping')
        database = mongo_client.chatdb
        logger.info("Connected to MongoDB")
    except Exception as e:
        logger.warning(f"MongoDB connection failed: {e}")
        database = None
    
    try:
        # Conectare Redis
        redis_client = redis.from_url(REDIS_URL, decode_responses=True, socket_connect_timeout=3)
        await redis_client.ping()
        redis_pubsub = redis_client.pubsub()
        await redis_pubsub.subscribe('chat')
        asyncio.create_task(redis_listener())
        logger.info("Connected to Redis")
    except Exception as e:
        logger.warning(f"Redis connection failed: {e}")
        redis_client = None
        redis_pubsub = None

@app.on_event("shutdown")
async def shutdown_event():
    global mongo_client, redis_client, redis_pubsub
    
    if redis_pubsub:
        await redis_pubsub.close()
    if redis_client:
        await redis_client.close()
    if mongo_client:
        mongo_client.close()

async def redis_listener():
    if not redis_pubsub:
        return
        
    try:
        async for message in redis_pubsub.listen():
            if message['type'] == 'message':
                await broadcast_to_websockets(message['data'])
    except Exception as e:
        logger.error(f"Redis listener error: {e}")

async def broadcast_to_websockets(message_json: str):
    if active_connections:
        disconnected = []
        for connection in active_connections:
            try:
                await connection.send_text(message_json)
            except:
                disconnected.append(connection)
        
        for conn in disconnected:
            if conn in active_connections:
                active_connections.remove(conn)

@app.get("/")
async def root():
    return {"status": "ok", "service": "chat-backend"}

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "mongodb": "connected" if database is not None else "disconnected",
        "redis": "connected" if redis_client is not None else "disconnected",
        "active_connections": len(active_connections)
    }

@app.get("/messages")
async def get_messages():
    try:
        if database is None:
            return []
            
        messages = []
        cursor = database.messages.find().sort("timestamp", 1)
        async for doc in cursor:
            messages.append({
                "username": doc["username"],
                "message": doc["message"],
                "timestamp": doc["timestamp"].isoformat()
            })
        return messages
    except Exception as e:
        logger.error(f"Error fetching messages: {e}")
        return []

@app.websocket("/")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    active_connections.append(websocket)
    
    try:
        await send_message_history(websocket)
        
        while True:
            data = await websocket.receive_text()
            await handle_websocket_message(data)
            
    except WebSocketDisconnect:
        pass
    except Exception as e:
        logger.error(f"WebSocket error: {e}")
    finally:
        if websocket in active_connections:
            active_connections.remove(websocket)

async def send_message_history(websocket: WebSocket):
    try:
        if database is None:
            response = {"type": "history", "data": []}
            await websocket.send_text(json.dumps(response))
            return
            
        messages = []
        cursor = database.messages.find().sort("timestamp", 1)
        async for doc in cursor:
            messages.append({
                "username": doc["username"],
                "message": doc["message"],
                "timestamp": doc["timestamp"].isoformat()
            })
        
        response = {"type": "history", "data": messages}
        await websocket.send_text(json.dumps(response))
    except Exception as e:
        logger.error(f"Error sending message history: {e}")

async def handle_websocket_message(raw_data: str):
    try:
        data = json.loads(raw_data)
        message_data = MessageData(**data)
        
        # Salvează în MongoDB
        timestamp = datetime.now()
        if database is not None:
            try:
                document = {
                    "username": message_data.username,
                    "message": message_data.text,
                    "timestamp": timestamp
                }
                await database.messages.insert_one(document)
            except Exception as e:
                logger.error(f"Error saving to MongoDB: {e}")
        
        # Publică pe Redis sau broadcast direct
        response = {
            "type": "message",
            "data": {
                "username": message_data.username,
                "message": message_data.text,
                "timestamp": timestamp.isoformat()
            }
        }
        
        response_json = json.dumps(response)
        
        if redis_client:
            try:
                await redis_client.publish('chat', response_json)
            except Exception as e:
                logger.error(f"Error publishing to Redis: {e}")
                await broadcast_to_websockets(response_json)
        else:
            await broadcast_to_websockets(response_json)
        
    except Exception as e:
        logger.error(f"Error handling WebSocket message: {e}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)