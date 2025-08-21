<template>
    <div id="app">
        <h1>Live Chat</h1>
        <div class="chat-container">
            <div class="messages" ref="messagesContainer">
                <div v-for="(msg, index) in messages" :key="index" class="message">
                    <strong>{{ msg.username }}</strong> ({{ formatTime(msg.timestamp) }}): {{ msg.message }}
                </div>
            </div>
            <div class="input-area">
                <input v-model="username" placeholder="Your Name" class="input-field" />
                <input v-model="newMessage" placeholder="Type a message..." class="input-field"
                    @keyup.enter="sendMessage" />
                <button @click="sendMessage" class="send-button">Send</button>
            </div>
            <div class="connection-status">
                <span :class="connectionStatusClass">{{ connectionStatus }}</span>
                <small v-if="wsUrl">Connecting to: {{ wsUrl }}</small>
            </div>
        </div>
    </div>
</template>

<script>
import moment from 'moment';

export default {
    name: 'App',
    data() {
        return {
            username: '',
            newMessage: '',
            messages: [],
            socket: null,
            connectionStatus: 'Connecting...',
            reconnectAttempts: 0,
            maxReconnectAttempts: 10,
            wsUrl: ''
        };
    },
    computed: {
        connectionStatusClass() {
            return {
                'status-connected': this.connectionStatus === 'Connected',
                'status-connecting': this.connectionStatus === 'Connecting...',
                'status-disconnected': this.connectionStatus.includes('Disconnected')
            };
        }
    },
    mounted() {
        this.connectWebSocket();
    },
    beforeUnmount() {
        if (this.socket) {
            this.socket.close();
        }
    },
    methods: {
        getPublicIP() {
            // Method 1: Check if we're in iframe and extract from parent URL
            try {
                if (window !== window.parent) {
                    // We're in an iframe (likely in Drupal)
                    const parentUrl = document.referrer || window.parent.location.href;
                    const ipMatch = parentUrl.match(/(\d+\.\d+\.\d+\.\d+)/);
                    if (ipMatch && ipMatch[1] !== '127.0.0.1' && ipMatch[1] !== '10.0.0.4') {
                        return ipMatch[1];
                    }
                }
            } catch (e) {
                // Cross-origin restriction, continue to other methods
            }

            // Method 2: Extract from current URL
            const currentUrl = window.location.href;
            const ipMatch = currentUrl.match(/(\d+\.\d+\.\d+\.\d+)/);
            if (ipMatch && ipMatch[1] !== '127.0.0.1' && ipMatch[1] !== '10.0.0.4') {
                return ipMatch[1];
            }

            // Method 3: Check hostname if it's an IP
            const hostname = window.location.hostname;
            if (/^\d+\.\d+\.\d+\.\d+$/.test(hostname) && hostname !== '127.0.0.1' && hostname !== '10.0.0.4') {
                return hostname;
            }

            // Method 4: Hardcoded fallback pentru Azure (din deployment-ul tău)
            return '135.235.170.64';
        },
        
        connectWebSocket() {
            try {
                const publicIP = this.getPublicIP();
                const wsPort = 30088; // NodePort pentru chat backend
                this.wsUrl = `ws://${publicIP}:${wsPort}`;
                
                console.log(`Attempting to connect to WebSocket: ${this.wsUrl}`);
                console.log(`Public IP detected: ${publicIP}`);
                this.connectionStatus = 'Connecting...';
                
                // Create WebSocket connection
                this.socket = new WebSocket(this.wsUrl);

                this.socket.onopen = () => {
                    console.log('Connected to WebSocket server');
                    this.connectionStatus = 'Connected';
                    this.reconnectAttempts = 0;
                };

                this.socket.onmessage = (event) => {
                    try {
                        const data = JSON.parse(event.data);

                        if (data.type === 'history') {
                            this.messages = data.data || [];
                            this.$nextTick(() => {
                                this.scrollToBottom();
                            });
                        } else if (data.type === 'message') {
                            this.messages.push(data.data);
                            this.$nextTick(() => {
                                this.scrollToBottom();
                            });
                        }
                    } catch (error) {
                        console.error('Error parsing WebSocket message:', error);
                    }
                };

                this.socket.onclose = (event) => {
                    console.log('Disconnected from WebSocket server', event);
                    this.connectionStatus = `Disconnected (attempt ${this.reconnectAttempts + 1}/${this.maxReconnectAttempts})`;
                    
                    // Try to reconnect after a delay if not manually closed
                    if (event.code !== 1000 && this.reconnectAttempts < this.maxReconnectAttempts) {
                        this.reconnectAttempts++;
                        const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000); // Exponential backoff, max 30s
                        setTimeout(() => {
                            this.connectWebSocket();
                        }, delay);
                    } else if (this.reconnectAttempts >= this.maxReconnectAttempts) {
                        this.connectionStatus = 'Connection failed - please refresh page';
                    }
                };

                this.socket.onerror = (error) => {
                    console.error('WebSocket error:', error);
                    this.connectionStatus = `Connection error to ${this.wsUrl}`;
                };
                
            } catch (error) {
                console.error('Failed to create WebSocket connection:', error);
                this.connectionStatus = 'Failed to create connection';
            }
        },
        
        sendMessage() {
            if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
                alert('Not connected to chat server. Please wait for connection or refresh the page.');
                return;
            }
            
            if (!this.newMessage.trim() || !this.username.trim()) {
                alert('Please enter both your name and a message.');
                return;
            }

            const message = {
                username: this.username.trim(),
                text: this.newMessage.trim()
            };

            try {
                this.socket.send(JSON.stringify(message));
                this.newMessage = '';
            } catch (error) {
                console.error('Failed to send message:', error);
                alert('Failed to send message. Please check connection and try again.');
            }
        },
        
        formatTime(timestamp) {
            return moment(timestamp).format('HH:mm:ss');
        },
        
        scrollToBottom() {
            if (this.$refs.messagesContainer) {
                this.$refs.messagesContainer.scrollTop = this.$refs.messagesContainer.scrollHeight;
            }
        }
    }
};
</script>

<style>
#app {
    font-family: Arial, sans-serif;
    max-width: 800px;
    margin: 0 auto;
    padding: 20px;
}

.chat-container {
    border: 1px solid #ccc;
    border-radius: 5px;
    overflow: hidden;
    background-color: white;
}

.messages {
    height: 400px;
    overflow-y: auto;
    padding: 10px;
    background-color: #f9f9f9;
}

.message {
    margin-bottom: 10px;
    padding: 8px;
    border-radius: 4px;
    background-color: white;
    border-left: 3px solid #4CAF50;
}

.input-area {
    display: flex;
    padding: 10px;
    background-color: #eee;
    gap: 10px;
}

.input-field {
    flex: 1;
    padding: 8px;
    border: 1px solid #ccc;
    border-radius: 3px;
    font-size: 14px;
}

.send-button {
    padding: 8px 15px;
    background-color: #4CAF50;
    color: white;
    border: none;
    border-radius: 3px;
    cursor: pointer;
    font-weight: bold;
}

.send-button:hover {
    background-color: #45a049;
}

.send-button:disabled {
    background-color: #ccc;
    cursor: not-allowed;
}

.connection-status {
    padding: 8px 10px;
    background-color: #f0f0f0;
    border-top: 1px solid #ddd;
    font-size: 12px;
    text-align: center;
}

.status-connected {
    color: #4CAF50;
    font-weight: bold;
}

.status-connecting {
    color: #ff9800;
    font-weight: bold;
}

.status-disconnected {
    color: #f44336;
    font-weight: bold;
}

.connection-status small {
    display: block;
    color: #666;
    margin-top: 2px;
}

/* Responsive design */
@media (max-width: 600px) {
    .input-area {
        flex-direction: column;
    }
    
    .input-field {
        margin-bottom: 8px;
    }
}
</style>