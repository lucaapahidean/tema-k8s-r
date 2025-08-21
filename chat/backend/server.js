/**
 * Chat back-end
 *  – Stores every message in MongoDB
 *  – Publishes it to Redis so *all* replicas see it
 *  – Listens on Redis to rebroadcast to each WebSocket client
 */

const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const mongoose = require('mongoose');
const cors = require('cors');
const { createClient } = require('redis');

const {
    PORT = 3000,
    MONGO_URL = 'mongodb://chat-db:27017/chatdb',
    REDIS_URL = 'redis://redis:6379',
} = process.env;

(async () => {
    await mongoose.connect(MONGO_URL, { useNewUrlParser: true, useUnifiedTopology: true });

    const messageSchema = new mongoose.Schema({
        username: { type: String, required: true },
        message: { type: String, required: true },
        timestamp: { type: Date, default: Date.now },
    });
    const Message = mongoose.model('Message', messageSchema);

    const pub = createClient({ url: REDIS_URL });
    const sub = pub.duplicate();
    await Promise.all([pub.connect(), sub.connect()]);

    const app = express();
    app.use(cors());
    app.use(express.json());
    app.get('/messages', async (_, res) => {
        res.json(await Message.find().sort({ timestamp: 1 }).lean());
    });

    const server = http.createServer(app);
    const wss = new WebSocket.Server({ server });

    const fanOut = (json) => {
        wss.clients.forEach(c => c.readyState === WebSocket.OPEN && c.send(json));
    };
    sub.subscribe('chat', fanOut);           // rebroadcast everything from Redis

    wss.on('connection', (ws) => {
        Message.find().sort({ timestamp: 1 }).lean().then((msgs) => {
            ws.send(JSON.stringify({ type: 'history', data: msgs }));
        });

        ws.on('message', async (raw) => {
            try {
                const { username, text } = JSON.parse(raw.toString());

                const doc = await Message.create({ username, message: text });

                const outbound = JSON.stringify({
                    type: 'message',
                    data: { username, message: text, timestamp: doc.timestamp },
                });
                await pub.publish('chat', outbound);   // every pod will fan-out
            } catch (err) {
                console.error('msg error:', err);
            }
        });
    });

    server.listen(PORT, () => console.log(`Chat backend ready on :${PORT}`));
})();