import React, { useState, useEffect, useRef } from 'react';
import moment from 'moment';
import './App.css';

function App() {
  const [username, setUsername] = useState('');
  const [newMessage, setNewMessage] = useState('');
  const [messages, setMessages] = useState([]);
  const [socket, setSocket] = useState(null);
  const [connectionStatus, setConnectionStatus] = useState('Connecting...');
  const [reconnectAttempts, setReconnectAttempts] = useState(0);
  
  const messagesContainerRef = useRef(null);
  const maxReconnectAttempts = 5;

  const getPublicIP = () => {
    try {
      if (window !== window.parent) {
        const parentUrl = document.referrer || window.parent.location.href;
        const ipMatch = parentUrl.match(/(\d+\.\d+\.\d+\.\d+)/);
        if (ipMatch && ipMatch[1] !== '127.0.0.1' && ipMatch[1] !== '10.0.0.4') {
          return ipMatch[1];
        }
      }
    } catch (e) {
      // Cross-origin restriction
    }

    const currentUrl = window.location.href;
    const ipMatch = currentUrl.match(/(\d+\.\d+\.\d+\.\d+)/);
    if (ipMatch && ipMatch[1] !== '127.0.0.1' && ipMatch[1] !== '10.0.0.4') {
      return ipMatch[1];
    }

    const hostname = window.location.hostname;
    if (/^\d+\.\d+\.\d+\.\d+$/.test(hostname) && hostname !== '127.0.0.1' && hostname !== '10.0.0.4') {
      return hostname;
    }

    return 'localhost';
  };

  const connectWebSocket = () => {
    try {
      const publicIP = getPublicIP();
      const wsPort = 30088;
      const websocketUrl = `ws://${publicIP}:${wsPort}`;
      
      setConnectionStatus('Connecting...');
      
      const ws = new WebSocket(websocketUrl);

      ws.onopen = () => {
        setConnectionStatus('Connected');
        setReconnectAttempts(0);
        setSocket(ws);
      };

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);

          if (data.type === 'history') {
            setMessages(data.data || []);
            scrollToBottom();
          } else if (data.type === 'message') {
            setMessages(prev => [...prev, data.data]);
            scrollToBottom();
          }
        } catch (error) {
          console.error('Error parsing WebSocket message:', error);
        }
      };

      ws.onclose = (event) => {
        setConnectionStatus('Disconnected');
        setSocket(null);
        
        if (event.code !== 1000 && reconnectAttempts < maxReconnectAttempts) {
          const newAttempts = reconnectAttempts + 1;
          setReconnectAttempts(newAttempts);
          setTimeout(() => {
            connectWebSocket();
          }, 2000 * newAttempts);
        } else if (reconnectAttempts >= maxReconnectAttempts) {
          setConnectionStatus('Connection failed - please refresh page');
        }
      };

      ws.onerror = () => {
        setConnectionStatus('Connection error');
      };
      
    } catch (error) {
      setConnectionStatus('Failed to create connection');
    }
  };

  const sendMessage = () => {
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      alert('Not connected to chat server. Please wait for connection or refresh the page.');
      return;
    }
    
    if (!newMessage.trim() || !username.trim()) {
      alert('Please enter both your name and a message.');
      return;
    }

    const message = {
      username: username.trim(),
      text: newMessage.trim()
    };

    try {
      socket.send(JSON.stringify(message));
      setNewMessage('');
    } catch (error) {
      alert('Failed to send message. Please check connection and try again.');
    }
  };

  const formatTime = (timestamp) => {
    return moment(timestamp).format('HH:mm:ss');
  };

  const scrollToBottom = () => {
    setTimeout(() => {
      if (messagesContainerRef.current) {
        messagesContainerRef.current.scrollTop = messagesContainerRef.current.scrollHeight;
      }
    }, 100);
  };

  const handleKeyPress = (event) => {
    if (event.key === 'Enter') {
      sendMessage();
    }
  };

  const getConnectionStatusClass = () => {
    if (connectionStatus === 'Connected') return 'status-connected';
    if (connectionStatus === 'Connecting...') return 'status-connecting';
    if (connectionStatus.includes('Disconnected')) return 'status-disconnected';
    return 'status-error';
  };

  useEffect(() => {
    connectWebSocket();
    
    return () => {
      if (socket) {
        socket.close();
      }
    };
  }, []);

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  return (
    <div id="app">
      <h1>Live Chat</h1>
      <div className="chat-container">
        <div className="messages" ref={messagesContainerRef}>
          {messages.length === 0 ? (
            <div style={{textAlign: 'center', color: '#666', fontStyle: 'italic', padding: '20px'}}>
              No messages yet. Start the conversation!
            </div>
          ) : (
            messages.map((msg, index) => (
              <div key={index} className="message">
                <strong>{msg.username}</strong> ({formatTime(msg.timestamp)}): {msg.message}
              </div>
            ))
          )}
        </div>
        <div className="input-area">
          <input
            type="text"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="Your Name"
            className="input-field"
          />
          <input
            type="text"
            value={newMessage}
            onChange={(e) => setNewMessage(e.target.value)}
            placeholder="Type a message..."
            className="input-field"
            onKeyPress={handleKeyPress}
          />
          <button onClick={sendMessage} className="send-button">
            Send
          </button>
        </div>
        <div className="connection-status">
          <span className={getConnectionStatusClass()}>{connectionStatus}</span>
          <small>Messages: {messages.length}</small>
        </div>
      </div>
    </div>
  );
}

export default App;