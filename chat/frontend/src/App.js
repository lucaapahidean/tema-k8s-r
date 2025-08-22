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
  const [wsUrl, setWsUrl] = useState('');
  
  const messagesContainerRef = useRef(null);
  const maxReconnectAttempts = 10;

  // Function to get public IP for WebSocket connection
  const getPublicIP = () => {
    try {
      // Check if we're in iframe and extract from parent URL
      if (window !== window.parent) {
        const parentUrl = document.referrer || window.parent.location.href;
        const ipMatch = parentUrl.match(/(\d+\.\d+\.\d+\.\d+)/);
        if (ipMatch && ipMatch[1] !== '127.0.0.1' && ipMatch[1] !== '10.0.0.4') {
          return ipMatch[1];
        }
      }
    } catch (e) {
      // Cross-origin restriction, continue to other methods
    }

    // Extract from current URL
    const currentUrl = window.location.href;
    const ipMatch = currentUrl.match(/(\d+\.\d+\.\d+\.\d+)/);
    if (ipMatch && ipMatch[1] !== '127.0.0.1' && ipMatch[1] !== '10.0.0.4') {
      return ipMatch[1];
    }

    // Check hostname if it's an IP
    const hostname = window.location.hostname;
    if (/^\d+\.\d+\.\d+\.\d+$/.test(hostname) && hostname !== '127.0.0.1' && hostname !== '10.0.0.4') {
      return hostname;
    }

    // Hardcoded fallback (update with your deployment IP)
    return '135.235.170.64';
  };

  // Connect to WebSocket
  const connectWebSocket = () => {
    try {
      const publicIP = getPublicIP();
      const wsPort = 30088; // NodePort pentru chat backend
      const websocketUrl = `ws://${publicIP}:${wsPort}`;
      
      setWsUrl(websocketUrl);
      console.log(`Attempting to connect to WebSocket: ${websocketUrl}`);
      console.log(`Public IP detected: ${publicIP}`);
      setConnectionStatus('Connecting...');
      
      const ws = new WebSocket(websocketUrl);

      ws.onopen = () => {
        console.log('Connected to WebSocket server');
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
        console.log('Disconnected from WebSocket server', event);
        setConnectionStatus(`Disconnected (attempt ${reconnectAttempts + 1}/${maxReconnectAttempts})`);
        setSocket(null);
        
        // Try to reconnect after a delay if not manually closed
        if (event.code !== 1000 && reconnectAttempts < maxReconnectAttempts) {
          const newAttempts = reconnectAttempts + 1;
          setReconnectAttempts(newAttempts);
          const delay = Math.min(1000 * Math.pow(2, newAttempts), 30000); // Exponential backoff, max 30s
          setTimeout(() => {
            connectWebSocket();
          }, delay);
        } else if (reconnectAttempts >= maxReconnectAttempts) {
          setConnectionStatus('Connection failed - please refresh page');
        }
      };

      ws.onerror = (error) => {
        console.error('WebSocket error:', error);
        setConnectionStatus(`Connection error to ${websocketUrl}`);
      };
      
    } catch (error) {
      console.error('Failed to create WebSocket connection:', error);
      setConnectionStatus('Failed to create connection');
    }
  };

  // Send message
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
      console.error('Failed to send message:', error);
      alert('Failed to send message. Please check connection and try again.');
    }
  };

  // Format timestamp
  const formatTime = (timestamp) => {
    return moment(timestamp).format('HH:mm:ss');
  };

  // Scroll to bottom
  const scrollToBottom = () => {
    setTimeout(() => {
      if (messagesContainerRef.current) {
        messagesContainerRef.current.scrollTop = messagesContainerRef.current.scrollHeight;
      }
    }, 100);
  };

  // Handle Enter key
  const handleKeyPress = (event) => {
    if (event.key === 'Enter') {
      sendMessage();
    }
  };

  // Connection status CSS class
  const getConnectionStatusClass = () => {
    if (connectionStatus === 'Connected') return 'status-connected';
    if (connectionStatus === 'Connecting...') return 'status-connecting';
    if (connectionStatus.includes('Disconnected')) return 'status-disconnected';
    return 'status-error';
  };

  // Connect on component mount
  useEffect(() => {
    connectWebSocket();
    
    // Cleanup on unmount
    return () => {
      if (socket) {
        socket.close();
      }
    };
  }, []); // Empty dependency array means this runs once on mount

  // Scroll to bottom when messages change
  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  return (
    <div id="app">
      <h1>Live Chat</h1>
      <div className="chat-container">
        <div className="messages" ref={messagesContainerRef}>
          {messages.map((msg, index) => (
            <div key={index} className="message">
              <strong>{msg.username}</strong> ({formatTime(msg.timestamp)}): {msg.message}
            </div>
          ))}
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
          {wsUrl && <small>Connecting to: {wsUrl}</small>}
        </div>
      </div>
    </div>
  );
}

export default App;