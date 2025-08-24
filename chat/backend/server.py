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

# Configurare logging mai detaliată
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
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
    
    logger.info(f"Starting up with MONGO_URL: {MONGO_URL}")
    
    try:
        # Conectare MongoDB cu setări mai explicite
        mongo_client = AsyncIOMotorClient(
            MONGO_URL,
            serverSelectionTimeoutMS=5000,
            connectTimeoutMS=5000,
            socketTimeoutMS=5000
        )
        
        # Test explicit connection
        await mongo_client.admin.command('ping')
        logger.info("MongoDB ping successful")
        
        # Explicitly select database
        database = mongo_client.get_database('chatdb')
        
        # Create index for messages
        await database.messages.create_index("timestamp")
        
        # Test write/read to verify connection
        test_doc = {"test": True, "timestamp": datetime.now()}
        result = await database.test.insert_one(test_doc)
        logger.info(f"Test document inserted with id: {result.inserted_id}")
        await database.test.delete_one({"_id": result.inserted_id})
        
        # Count existing messages
        count = await database.messages.count_documents({})
        logger.info(f"MongoDB connected successfully. Existing messages: {count}")
        
    except Exception as e:
        logger.error(f"MongoDB connection failed: {e}", exc_info=True)
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
                logger.debug(f"Redis message received: {message['data'][:100]}...")
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
    mongo_status = "disconnected"
    message_count = 0
    
    if database is not None:
        try:
            await mongo_client.admin.command('ping')
            mongo_status = "connected"
            message_count = await database.messages.count_documents({})
        except:
            mongo_status = "error"
    
    return {
        "status": "ok",
        "mongodb": mongo_status,
        "redis": "connected" if redis_client is not None else "disconnected",
        "active_connections": len(active_connections),
        "total_messages": message_count
    }

@app.get("/messages")
async def get_messages():
    try:
        if database is None:
            logger.warning("Database not connected when fetching messages via HTTP")
            return []
        
        # Get all messages, sorted by timestamp
        messages = []
        cursor = database.messages.find({}).sort("timestamp", 1).limit(100)
        
        async for doc in cursor:
            try:
                msg = {
                    "username": doc.get("username", "Unknown"),
                    "message": doc.get("message", ""),
                    "timestamp": doc.get("timestamp", datetime.now()).isoformat()
                }
                messages.append(msg)
            except Exception as e:
                logger.error(f"Error processing document: {e}")
        
        logger.info(f"HTTP GET /messages returned {len(messages)} messages")
        return messages
        
    except Exception as e:
        logger.error(f"Error fetching messages via HTTP: {e}", exc_info=True)
        return []

@app.websocket("/")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    active_connections.append(websocket)
    logger.info(f"New WebSocket connection established. Total connections: {len(active_connections)}")
    
    try:
        # Send message history immediately after connection
        await send_message_history(websocket)
        
        # Handle incoming messages
        while True:
            data = await websocket.receive_text()
            logger.debug(f"Received WebSocket message: {data[:100]}...")
            await handle_websocket_message(data)
            
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected normally")
    except Exception as e:
        logger.error(f"WebSocket error: {e}", exc_info=True)
    finally:
        if websocket in active_connections:
            active_connections.remove(websocket)
        logger.info(f"WebSocket closed. Remaining connections: {len(active_connections)}")

async def send_message_history(websocket: WebSocket):
    """Send chat history to newly connected client"""
    try:
        logger.info("Attempting to send message history to new client...")
        
        if database is None:
            logger.warning("Database is None - sending empty history")
            response = {"type": "history", "data": []}
            await websocket.send_text(json.dumps(response))
            return
        
        # Verifică conexiunea la MongoDB
        try:
            await mongo_client.admin.command('ping')
        except Exception as e:
            logger.error(f"MongoDB ping failed when sending history: {e}")
            response = {"type": "history", "data": []}
            await websocket.send_text(json.dumps(response))
            return
        
        # Fetch messages from MongoDB
        messages = []
        try:
            # Use a simple find with limit
            cursor = database.messages.find({}).sort("timestamp", 1).limit(100)
            
            # Convert cursor to list
            docs = await cursor.to_list(length=100)
            logger.info(f"Retrieved {len(docs)} documents from MongoDB")
            
            for doc in docs:
                try:
                    msg = {
                        "username": str(doc.get("username", "Unknown")),
                        "message": str(doc.get("message", "")),
                        "timestamp": doc.get("timestamp", datetime.now()).isoformat() if doc.get("timestamp") else datetime.now().isoformat()
                    }
                    messages.append(msg)
                    logger.debug(f"Processed message: {msg['username']}: {msg['message'][:50]}...")
                except Exception as e:
                    logger.error(f"Error processing individual document: {e}, doc: {doc}")
                    continue
                    
        except Exception as e:
            logger.error(f"Error fetching documents from MongoDB: {e}", exc_info=True)
        
        # Send the history to client
        response = {"type": "history", "data": messages}
        response_json = json.dumps(response)
        await websocket.send_text(response_json)
        logger.info(f"Successfully sent {len(messages)} historical messages to client")
        
    except Exception as e:
        logger.error(f"Critical error in send_message_history: {e}", exc_info=True)
        try:
            # Try to send empty history as fallback
            response = {"type": "history", "data": []}
            await websocket.send_text(json.dumps(response))
            logger.info("Sent empty history as fallback")
        except Exception as e2:
            logger.error(f"Failed to send even empty history: {e2}")

async def handle_websocket_message(raw_data: str):
    """Handle incoming message from WebSocket client"""
    try:
        data = json.loads(raw_data)
        logger.debug(f"Parsed message data: {data}")
        
        message_data = MessageData(**data)
        
        # Prepare timestamp
        timestamp = datetime.now()
        
        # Save to MongoDB if connected
        saved_to_db = False
        if database is not None:
            try:
                document = {
                    "username": message_data.username,
                    "message": message_data.text,  # Note: saving 'text' as 'message'
                    "timestamp": timestamp
                }
                result = await database.messages.insert_one(document)
                logger.info(f"Message saved to MongoDB with id: {result.inserted_id}")
                saved_to_db = True
                
                # Verify the save by reading it back
                saved_doc = await database.messages.find_one({"_id": result.inserted_id})
                if saved_doc:
                    logger.debug(f"Verified saved document: {saved_doc}")
                else:
                    logger.error("Could not verify saved document!")
                    
            except Exception as e:
                logger.error(f"Error saving to MongoDB: {e}", exc_info=True)
        else:
            logger.warning("Database not connected - message not persisted")
        
        # Prepare response for broadcast
        response = {
            "type": "message",
            "data": {
                "username": message_data.username,
                "message": message_data.text,  # Note: sending as 'message' to match history format
                "timestamp": timestamp.isoformat()
            }
        }
        
        response_json = json.dumps(response)
        logger.debug(f"Broadcasting message: {response_json[:100]}...")
        
        # Publish to Redis or broadcast directly
        if redis_client:
            try:
                await redis_client.publish('chat', response_json)
                logger.debug("Message published to Redis")
            except Exception as e:
                logger.error(f"Error publishing to Redis: {e}")
                await broadcast_to_websockets(response_json)
        else:
            await broadcast_to_websockets(response_json)
        
        logger.info(f"Message from {message_data.username} processed successfully (saved_to_db: {saved_to_db})")
        
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON received: {e}")
    except Exception as e:
        logger.error(f"Error handling WebSocket message: {e}", exc_info=True)

@app.get("/debug/messages")
async def debug_messages():
    """Debug endpoint to check database content"""
    if database is None:
        return {"error": "Database not connected"}
    
    try:
        count = await database.messages.count_documents({})
        
        # Get last 5 messages
        cursor = database.messages.find({}).sort("timestamp", -1).limit(5)
        recent = []
        async for doc in cursor:
            recent.append({
                "id": str(doc.get("_id")),
                "username": doc.get("username"),
                "message": doc.get("message"),
                "timestamp": str(doc.get("timestamp"))
            })
        
        return {
            "total_count": count,
            "recent_messages": recent,
            "database_name": database.name,
            "collection_names": await database.list_collection_names()
        }
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="debug")