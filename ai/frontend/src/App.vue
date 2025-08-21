<template>
    <div id="app">
        <h1>OCR Image Recognition</h1>
        <div class="upload-container">
            <input type="file" @change="onFileSelected" accept="image/*" ref="fileInput" class="file-input" />
            <button @click="uploadFile" :disabled="!selectedFile || isUploading" class="upload-button">
                {{ isUploading ? 'Uploading...' : 'Upload & Process' }}
            </button>
        </div>

        <div v-if="isProcessing" class="loading">
            Processing image with Azure OCR...
        </div>

        <div v-if="error" class="error">
            {{ error }}
        </div>

        <div v-if="ocrResult" class="result">
            <h2>OCR Result:</h2>
            <pre>{{ ocrResult }}</pre>
        </div>

        <div class="history">
            <h2>Processing History</h2>
            <button @click="refreshHistory" class="refresh-button" :disabled="isLoadingHistory">
                {{ isLoadingHistory ? 'Loading...' : 'Refresh History' }}
            </button>
            <table v-if="history.length > 0">
                <thead>
                    <tr>
                        <th>ID</th>
                        <th>Filename</th>
                        <th>Date</th>
                        <th>Action</th>
                    </tr>
                </thead>
                <tbody>
                    <tr v-for="item in history" :key="item.Id">
                        <td>{{ item.Id }}</td>
                        <td>{{ item.Filename }}</td>
                        <td>{{ formatDate(item.ProcessedAt) }}</td>
                        <td>
                            <button @click="showResult(item)" class="view-button">View Result</button>
                            <a :href="item.BlobUrl" target="_blank" class="download-link">View Image</a>
                        </td>
                    </tr>
                </tbody>
            </table>
            <p v-else-if="!isLoadingHistory">No processing history yet.</p>
        </div>
    </div>
</template>

<script>
import axios from 'axios';

export default {
    name: 'App',
    data() {
        return {
            selectedFile: null,
            isUploading: false,
            isProcessing: false,
            isLoadingHistory: false,
            ocrResult: null,
            error: null,
            history: [],
            // NodePort - foloseste IP-ul nodului si portul NodePort pentru AI backend
            backendUrl: `http://${window.location.hostname}:30101/api`
        };
    },
    created() {
        this.fetchHistory();
    },
    methods: {
        onFileSelected(event) {
            this.selectedFile = event.target.files[0];
            this.error = null;
            this.ocrResult = null;
        },
        async uploadFile() {
            if (!this.selectedFile) {
                this.error = 'Please select a file first';
                return;
            }

            this.isUploading = true;
            this.isProcessing = true;
            this.error = null;

            try {
                const formData = new FormData();
                formData.append('image', this.selectedFile);

                const response = await axios.post(`${this.backendUrl}/process-image`, formData, {
                    headers: {
                        'Content-Type': 'multipart/form-data'
                    },
                    timeout: 30000
                });

                if (response.data.success) {
                    this.ocrResult = response.data.ocrResult;
                    await this.fetchHistory();
                    this.$refs.fileInput.value = '';
                    this.selectedFile = null;
                } else {
                    this.error = 'Failed to process image';
                }

            } catch (err) {
                console.error('Upload error:', err);
                if (err.response) {
                    this.error = `Server Error: ${err.response.data.error || err.response.statusText}`;
                } else if (err.request) {
                    this.error = 'Network error: Could not connect to server';
                } else {
                    this.error = `Error: ${err.message}`;
                }
            } finally {
                this.isUploading = false;
                this.isProcessing = false;
            }
        },
        async fetchHistory() {
            this.isLoadingHistory = true;
            try {
                const response = await axios.get(`${this.backendUrl}/history`);
                if (response.data.success) {
                    this.history = response.data.history;
                }
            } catch (err) {
                console.error('Error fetching history:', err);
            } finally {
                this.isLoadingHistory = false;
            }
        },
        async refreshHistory() {
            await this.fetchHistory();
        },
        showResult(item) {
            this.ocrResult = item.OcrResult;
        },
        formatDate(date) {
            return new Date(date).toLocaleString('ro-RO');
        }
    }
};
</script>

<style>
#app {
    font-family: Arial, sans-serif;
    max-width: 1000px;
    margin: 0 auto;
    padding: 20px;
}

.upload-container {
    display: flex;
    margin-bottom: 20px;
}

.file-input {
    flex: 1;
    padding: 10px;
    border: 1px solid #ccc;
    border-radius: 3px;
}

.upload-button {
    padding: 10px 20px;
    background-color: #4CAF50;
    color: white;
    border: none;
    border-radius: 3px;
    cursor: pointer;
    margin-left: 10px;
}

.upload-button:disabled {
    background-color: #ccc;
    cursor: not-allowed;
}

.refresh-button {
    padding: 8px 15px;
    background-color: #2196f3;
    color: white;
    border: none;
    border-radius: 3px;
    cursor: pointer;
    margin-bottom: 15px;
}

.refresh-button:disabled {
    background-color: #ccc;
    cursor: not-allowed;
}

.loading {
    padding: 10px;
    background-color: #fffde7;
    border: 1px solid #ffd600;
    border-radius: 3px;
    margin-bottom: 20px;
}

.error {
    padding: 10px;
    background-color: #ffebee;
    border: 1px solid #f44336;
    border-radius: 3px;
    margin-bottom: 20px;
}

.result {
    padding: 10px;
    background-color: #e8f5e9;
    border: 1px solid #4caf50;
    border-radius: 3px;
    margin-bottom: 20px;
}

pre {
    white-space: pre-wrap;
    word-wrap: break-word;
    max-height: 300px;
    overflow-y: auto;
}

.history {
    margin-top: 30px;
}

table {
    width: 100%;
    border-collapse: collapse;
}

th,
td {
    padding: 10px;
    text-align: left;
    border-bottom: 1px solid #ddd;
}

.view-button {
    padding: 5px 10px;
    background-color: #2196f3;
    color: white;
    border: none;
    border-radius: 3px;
    cursor: pointer;
    margin-right: 5px;
    font-size: 12px;
}

.download-link {
    padding: 5px 10px;
    background-color: #ff9800;
    color: white;
    text-decoration: none;
    border-radius: 3px;
    font-size: 12px;
}

.download-link:hover {
    background-color: #f57c00;
}
</style>