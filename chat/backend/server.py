import os
import json
import asyncio
import logging
from datetime import datetime
from typing import List, Dict, Any

import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
import redis.asyncio as redis
from pydantic import BaseModel

# Configurare logging cu mai mult detaliu
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(name)s - %(message)s')
logger = logging.getLogger(__name__)

# Configurare din environment
PORT = int(os.getenv('PORT', 3000))
MONGO_URL = os.getenv('MONGO_URL', 'mongodb://chat-db:27017/chatdb')
REDIS_URL = os.getenv('REDIS_URL', 'redis://redis:6379')

logger.info(f"🚀 Starting chat backend on port {PORT}")
logger.info(f"🍃 MongoDB URL: {MONGO_URL}")
logger.info(f"🔴 Redis URL: {REDIS_URL}")

# Modele Pydantic
class Message(BaseModel):
    username: str
    message: str
    timestamp: datetime = None

class MessageData(BaseModel):
    username: str
    text: str

# FastAPI app
app = FastAPI(title="Chat Backend Debug")

# CORS configuration
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
    """Inițializare conexiuni la startup"""
    global mongo_client, database, redis_client, redis_pubsub
    
    logger.info("🚀 Starting up Chat Backend...")
    
    try:
        # Conectare MongoDB cu retry
        logger.info("🍃 Connecting to MongoDB...")
        for attempt in range(3):
            try:
                mongo_client = AsyncIOMotorClient(MONGO_URL, serverSelectionTimeoutMS=5000)
                # Test connection
                await mongo_client.admin.command('ping')
                database = mongo_client.chatdb
                logger.info("✅ Connected to MongoDB successfully")
                break
            except Exception as e:
                logger.warning(f"⚠️ MongoDB connection attempt {attempt + 1} failed: {e}")
                if attempt == 2:
                    logger.error("❌ Failed to connect to MongoDB after 3 attempts, continuing without MongoDB")
                    database = None
                else:
                    await asyncio.sleep(2)
        
        # Conectare Redis pentru pub/sub cu retry
        logger.info("🔴 Connecting to Redis...")
        for attempt in range(3):
            try:
                redis_client = redis.from_url(REDIS_URL, decode_responses=True, socket_connect_timeout=5)
                # Test connection
                await redis_client.ping()
                redis_pubsub = redis_client.pubsub()
                await redis_pubsub.subscribe('chat')
                
                # Start Redis listener în background
                asyncio.create_task(redis_listener())
                logger.info("✅ Connected to Redis successfully")
                break
            except Exception as e:
                logger.warning(f"⚠️ Redis connection attempt {attempt + 1} failed: {e}")
                if attempt == 2:
                    logger.error("❌ Failed to connect to Redis after 3 attempts, continuing without Redis")
                    redis_client = None
                    redis_pubsub = None
                else:
                    await asyncio.sleep(2)
        
        logger.info("🎉 Chat Backend startup completed")
        
    except Exception as e:
        logger.error(f"❌ Error during startup: {e}")
        # Continue running even if some services are not available

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup la shutdown"""
    global mongo_client, redis_client, redis_pubsub
    
    logger.info("⏹️ Shutting down Chat Backend...")
    
    if redis_pubsub:
        await redis_pubsub.close()
    if redis_client:
        await redis_client.close()
    if mongo_client:
        mongo_client.close()

async def redis_listener():
    """Ascultă mesajele de pe Redis și le retransmite la toate conexiunile WebSocket"""
    if not redis_pubsub:
        logger.warning("⚠️ Redis pubsub not available, skipping listener")
        return
        
    logger.info("🔴 Starting Redis listener...")
    try:
        async for message in redis_pubsub.listen():
            logger.debug(f"🔴 Redis message received: {message}")
            if message['type'] == 'message':
                data = message['data']
                logger.info(f"📢 Broadcasting message from Redis: {data}")
                await broadcast_to_websockets(data)
    except Exception as e:
        logger.error(f"❌ Redis listener error: {e}")

async def broadcast_to_websockets(message_json: str):
    """Trimite un mesaj la toate conexiunile WebSocket active"""
    logger.info(f"📡 Broadcasting to {len(active_connections)} connections: {message_json}")
    if active_connections:
        disconnected = []
        for i, connection in enumerate(active_connections):
            try:
                await connection.send_text(message_json)
                logger.debug(f"✅ Sent to connection {i}")
            except Exception as e:
                logger.warning(f"⚠️ Failed to send to connection {i}: {e}")
                disconnected.append(connection)
        
        # Șterge conexiunile inactive
        for conn in disconnected:
            if conn in active_connections:
                active_connections.remove(conn)
                logger.info(f"🗑️ Removed disconnected connection")

@app.get("/")
async def root():
    """Root endpoint pentru health check"""
    logger.debug("🏠 Root endpoint accessed")
    return {"status": "ok", "service": "chat-backend-debug"}

@app.get("/health")
async def health():
    """Health check endpoint"""
    logger.debug("❤️ Health check accessed")
    health_status = {
        "status": "ok",
        "mongodb": "connected" if database is not None else "disconnected",
        "redis": "connected" if redis_client is not None else "disconnected",
        "active_connections": len(active_connections)
    }
    logger.info(f"❤️ Health status: {health_status}")
    return health_status

@app.get("/messages")
async def get_messages():
    """Endpoint REST pentru a obține istoricul mesajelor"""
    logger.info("📚 Getting message history")
    try:
        if database is None:
            logger.warning("⚠️ No database available, returning empty history")
            return []
            
        messages = []
        cursor = database.messages.find().sort("timestamp", 1)
        async for doc in cursor:
            messages.append({
                "username": doc["username"],
                "message": doc["message"],
                "timestamp": doc["timestamp"].isoformat()
            })
        logger.info(f"📚 Returning {len(messages)} messages")
        return messages
    except Exception as e:
        logger.error(f"❌ Error fetching messages: {e}")
        return []

@app.websocket("/")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint pentru chat"""
    await websocket.accept()
    active_connections.append(websocket)
    logger.info(f"🔌 New WebSocket connection. Total: {len(active_connections)}")
    
    try:
        # Trimite istoricul mesajelor la conectare
        await send_message_history(websocket)
        
        # Ascultă pentru mesaje noi
        while True:
            data = await websocket.receive_text()
            logger.info(f"📨 Received WebSocket data: {data}")
            await handle_websocket_message(data)
            
    except WebSocketDisconnect:
        logger.info("🔌 WebSocket disconnected normally")
    except Exception as e:
        logger.error(f"❌ WebSocket error: {e}")
    finally:
        if websocket in active_connections:
            active_connections.remove(websocket)
        logger.info(f"🔌 WebSocket connection removed. Total: {len(active_connections)}")

async def send_message_history(websocket: WebSocket):
    """Trimite istoricul mesajelor la o conexiune nouă"""
    logger.info("📚 Sending message history to new connection")
    try:
        if database is None:
            # Trimite istoric gol dacă nu avem MongoDB
            response = {"type": "history", "data": []}
            await websocket.send_text(json.dumps(response))
            logger.info("📚 Sent empty history (no database)")
            return
            
        messages = []
        cursor = database.messages.find().sort("timestamp", 1)
        async for doc in cursor:
            messages.append({
                "username": doc["username"],
                "message": doc["message"],
                "timestamp": doc["timestamp"].isoformat()
            })
        
        response = {
            "type": "history",
            "data": messages
        }
        response_json = json.dumps(response)
        await websocket.send_text(response_json)
        logger.info(f"📚 Sent {len(messages)} historical messages: {response_json}")
    except Exception as e:
        logger.error(f"❌ Error sending message history: {e}")

async def handle_websocket_message(raw_data: str):
    """Procesează un mesaj primit prin WebSocket"""
    logger.info(f"🔄 Processing WebSocket message: {raw_data}")
    try:
        data = json.loads(raw_data)
        logger.info(f"🔄 Parsed JSON data: {data}")
        
        message_data = MessageData(**data)
        logger.info(f"🔄 Created MessageData: username='{message_data.username}', text='{message_data.text}'")
        
        # Salvează în MongoDB dacă este disponibil
        timestamp = datetime.now()
        if database is not None:
            try:
                document = {
                    "username": message_data.username,
                    "message": message_data.text,
                    "timestamp": timestamp
                }
                
                result = await database.messages.insert_one(document)
                logger.info(f"🍃 Saved message to MongoDB: {result.inserted_id}")
            except Exception as e:
                logger.error(f"❌ Error saving to MongoDB: {e}")
        else:
            logger.warning("⚠️ No MongoDB available, message not saved")
        
        # Publică pe Redis pentru toate replicile sau broadcast direct
        response = {
            "type": "message",
            "data": {
                "username": message_data.username,
                "message": message_data.text,
                "timestamp": timestamp.isoformat()
            }
        }
        
        response_json = json.dumps(response)
        logger.info(f"📤 Prepared response: {response_json}")
        
        if redis_client:
            try:
                await redis_client.publish('chat', response_json)
                logger.info("🔴 Published message to Redis")
            except Exception as e:
                logger.error(f"❌ Error publishing to Redis: {e}")
                # Fallback: broadcast direct la conexiunile locale
                logger.info("🔄 Falling back to direct broadcast")
                await broadcast_to_websockets(response_json)
        else:
            # Dacă nu avem Redis, broadcast direct la conexiunile locale
            logger.info("🔄 No Redis, using direct broadcast")
            await broadcast_to_websockets(response_json)
        
    except Exception as e:
        logger.error(f"❌ Error handling WebSocket message: {e}")
        logger.error(f"❌ Raw data was: {raw_data}")

if __name__ == "__main__":
    logger.info(f"🚀 Starting uvicorn server on 0.0.0.0:{PORT}")
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=PORT,
        log_level="debug",
        access_log=True
    )