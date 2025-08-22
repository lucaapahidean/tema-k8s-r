import React, { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import moment from 'moment';
import './App.css';

function App() {
  const [selectedFile, setSelectedFile] = useState(null);
  const [isUploading, setIsUploading] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [isLoadingHistory, setIsLoadingHistory] = useState(false);
  const [imageDescription, setImageDescription] = useState(null);
  const [error, setError] = useState(null);
  const [history, setHistory] = useState([]);
  const fileInputRef = useRef(null);

  // Backend URL - foloseste IP-ul nodului si portul NodePort pentru AI backend
  const backendUrl = `http://${window.location.hostname}:30101/api`;

  useEffect(() => {
    fetchHistory();
  }, []);

  const onFileSelected = (event) => {
    const file = event.target.files[0];
    if (file) {
      // Verifică dacă este imagine
      if (!file.type.startsWith('image/')) {
        setError('Please select a valid image file (jpg, png, gif, etc.)');
        return;
      }
      
      // Verifică dimensiunea (max 10MB)
      if (file.size > 10 * 1024 * 1024) {
        setError('File size must be less than 10MB');
        return;
      }
      
      setSelectedFile(file);
      setError(null);
      setImageDescription(null);
    }
  };

  const uploadFile = async () => {
    if (!selectedFile) {
      setError('Please select an image file first');
      return;
    }

    setIsUploading(true);
    setIsProcessing(true);
    setError(null);

    try {
      const formData = new FormData();
      formData.append('image', selectedFile);

      const response = await axios.post(`${backendUrl}/process-image`, formData, {
        headers: {
          'Content-Type': 'multipart/form-data'
        },
        timeout: 60000 // 60 secunde timeout pentru procesarea AI
      });

      if (response.data.success) {
        setImageDescription(response.data.imageDescription);
        await fetchHistory();
        
        // Resetează form-ul
        if (fileInputRef.current) {
          fileInputRef.current.value = '';
        }
        setSelectedFile(null);
      } else {
        setError('Failed to process image');
      }

    } catch (err) {
      console.error('Upload error:', err);
      if (err.response) {
        const errorMsg = err.response.data?.error || err.response.statusText;
        const details = err.response.data?.details ? ` - ${err.response.data.details}` : '';
        setError(`Server Error: ${errorMsg}${details}`);
      } else if (err.request) {
        setError('Network error: Could not connect to AI service. Please check if the backend is running.');
      } else {
        setError(`Error: ${err.message}`);
      }
    } finally {
      setIsUploading(false);
      setIsProcessing(false);
    }
  };

  const fetchHistory = async () => {
    setIsLoadingHistory(true);
    try {
      const response = await axios.get(`${backendUrl}/history`, {
        timeout: 10000
      });
      
      if (response.data.success) {
        setHistory(response.data.history || []);
      }
    } catch (err) {
      console.error('Error fetching history:', err);
      // Nu afișăm eroare pentru history deoarece nu e critică
    } finally {
      setIsLoadingHistory(false);
    }
  };

  const refreshHistory = async () => {
    await fetchHistory();
  };

  const showResult = (item) => {
    setImageDescription(item.ImageDescription);
    setError(null);
  };

  const formatDate = (date) => {
    return moment(date).format('DD/MM/YYYY HH:mm:ss');
  };

  const formatFileSize = (bytes) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  return (
    <div id="app">
      <h1>AI Image Description</h1>
      
      <div className="upload-container">
        <div className="upload-area">
          <input
            type="file"
            onChange={onFileSelected}
            accept="image/*"
            ref={fileInputRef}
            className="file-input"
            disabled={isUploading}
          />
          <button 
            onClick={uploadFile} 
            disabled={!selectedFile || isUploading} 
            className="upload-button"
          >
            {isUploading ? 'Processing...' : 'Upload & Analyze'}
          </button>
        </div>
        
        {selectedFile && (
          <div className="status-indicator">
            Selected: {selectedFile.name} ({formatFileSize(selectedFile.size)})
          </div>
        )}
      </div>

      {isProcessing && (
        <div className="loading">
          Analyzing image with Azure Computer Vision AI...
          <br />
          <small>This may take a few moments</small>
        </div>
      )}

      {error && (
        <div className="error">
          {error}
        </div>
      )}

      {imageDescription && (
        <div className="result-container">
          <div className="result">
            <h2>AI Image Analysis Result</h2>
            <div className="result-text">{imageDescription}</div>
          </div>
        </div>
      )}

      <div className="history">
        <div className="history-container">
          <div className="history-header">
            <h2>Processing History</h2>
            <button 
              onClick={refreshHistory} 
              className="refresh-button" 
              disabled={isLoadingHistory}
            >
              {isLoadingHistory ? 'Loading...' : 'Refresh'}
            </button>
          </div>
          
          <div className="history-content">
            {history.length > 0 ? (
              <table>
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Filename</th>
                    <th>Processed Date</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {history.map((item) => (
                    <tr key={item.Id}>
                      <td>#{item.Id}</td>
                      <td title={item.Filename}>
                        {item.Filename.length > 30 
                          ? item.Filename.substring(0, 30) + '...' 
                          : item.Filename}
                      </td>
                      <td>{formatDate(item.ProcessedAt)}</td>
                      <td>
                        <button 
                          onClick={() => showResult(item)} 
                          className="view-button"
                          title="View AI description"
                        >
                          View Result
                        </button>
                        <a 
                          href={item.BlobUrl} 
                          target="_blank" 
                          rel="noopener noreferrer"
                          className="download-link"
                          title="Open original image"
                        >
                          View Image
                        </a>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : (
              <div className="no-history">
                {isLoadingHistory 
                  ? 'Loading processing history...' 
                  : 'No images processed yet. Upload an image to get started!'}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;