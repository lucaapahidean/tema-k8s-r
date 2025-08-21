const express = require('express');
const multer = require('multer');
const { BlobServiceClient } = require('@azure/storage-blob');
const { ComputerVisionClient } = require('@azure/cognitiveservices-computervision');
const { CognitiveServicesCredentials } = require('@azure/ms-rest-azure-js');
const sql = require('mssql');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const app = express();
app.use(cors());
app.use(express.json());

// Configurari Azure din variabile de mediu
const azureConfig = {
    storageConnectionString: process.env.AZURE_STORAGE_CONNECTION_STRING,
    containerName: process.env.AZURE_CONTAINER_NAME || 'images',
    ocrEndpoint: process.env.AZURE_OCR_ENDPOINT,
    ocrApiKey: process.env.AZURE_OCR_API_KEY,
    sqlConnectionString: process.env.AZURE_SQL_CONNECTION_STRING
};

// Functie pentru parsarea connection string-ului SQL
function parseSqlConnectionString(connectionString) {
    const params = {};

    if (!connectionString) {
        throw new Error('SQL connection string is not provided');
    }

    // Lista de parametri cunoscuti pentru a identifica sfarsitul parolei
    const knownParams = [
        'server', 'initial catalog', 'persist security info', 'user id', 'password',
        'multipleactiveresultsets', 'encrypt', 'trustservercertificate', 'connection timeout'
    ];

    // Parsare specifica pentru connection string-uri SQL Server
    let remaining = connectionString;

    while (remaining.length > 0) {
        // Gaseste urmatorul parametru
        let foundParam = null;
        let paramStart = -1;

        for (const param of knownParams) {
            const index = remaining.toLowerCase().indexOf(param + '=');
            if (index !== -1 && (paramStart === -1 || index < paramStart)) {
                paramStart = index;
                foundParam = param;
            }
        }

        if (paramStart === -1) break;

        // Extrage numele parametrului
        const paramName = foundParam;
        const valueStart = paramStart + paramName.length + 1;

        // Pentru parola, cauta urmatorul parametru cunoscut
        let valueEnd = remaining.length;
        if (paramName === 'password') {
            for (const nextParam of knownParams) {
                if (nextParam === 'password') continue;
                const nextIndex = remaining.toLowerCase().indexOf(';' + nextParam + '=', valueStart);
                if (nextIndex !== -1 && nextIndex < valueEnd) {
                    valueEnd = nextIndex;
                }
            }
        } else {
            // Pentru alti parametri, cauta urmatorul ';'
            const nextSemicolon = remaining.indexOf(';', valueStart);
            if (nextSemicolon !== -1) {
                valueEnd = nextSemicolon;
            }
        }

        // Extrage valoarea
        const value = remaining.substring(valueStart, valueEnd).trim();
        params[paramName.toLowerCase()] = value;

        // Continua cu restul string-ului
        remaining = remaining.substring(valueEnd + 1);
    }

    // Mapeaza parametrii la configuratia mssql
    const config = {
        server: params.server?.replace('tcp:', '').split(',')[0],
        database: params['initial catalog'],
        user: params['user id'],
        password: params.password,
        port: parseInt(params.server?.split(',')[1]) || 1433,
        options: {
            encrypt: params.encrypt === 'True' || params.encrypt === 'true',
            trustServerCertificate: params.trustservercertificate === 'True' || params.trustservercertificate === 'true',
            enableArithAbort: true
        },
        connectionTimeout: parseInt(params['connection timeout']) * 1000 || 30000,
        requestTimeout: 30000
    };

    console.log('Parsed SQL config (without password):', {
        server: config.server,
        database: config.database,
        user: config.user,
        port: config.port,
        passwordLength: config.password?.length,
        options: config.options
    });

    return config;
}

// Configurare SQL Server folosind connection string-ul din secrets
let sqlConfig;
try {
    sqlConfig = parseSqlConnectionString(azureConfig.sqlConnectionString);
    console.log('SQL configuration parsed successfully');
} catch (err) {
    console.error('Error parsing SQL connection string:', err.message);
    process.exit(1);
}

// Configurare multer pentru upload-ul fisierelor
const upload = multer({ dest: 'uploads/' });

// Initializare Azure Blob Storage
let blobServiceClient;
try {
    if (azureConfig.storageConnectionString) {
        blobServiceClient = BlobServiceClient.fromConnectionString(azureConfig.storageConnectionString);
        console.log('Azure Blob Storage client initialized');
    } else {
        console.warn('Azure Storage connection string not provided');
    }
} catch (err) {
    console.error('Error initializing Blob Storage:', err.message);
}

// Initializare Azure Computer Vision pentru OCR
let computerVisionClient;
try {
    if (azureConfig.ocrApiKey && azureConfig.ocrEndpoint) {
        const cognitiveServiceCredentials = new CognitiveServicesCredentials(azureConfig.ocrApiKey);
        computerVisionClient = new ComputerVisionClient(cognitiveServiceCredentials, azureConfig.ocrEndpoint);
        console.log('Azure Computer Vision client initialized');
    } else {
        console.warn('Azure OCR credentials not provided');
    }
} catch (err) {
    console.error('Error initializing Computer Vision:', err.message);
}

// Initializeaza tabela daca nu exista
async function initializeDatabase() {
    try {
        console.log('Attempting to connect to database...');
        await sql.connect(sqlConfig);
        console.log('Database connected successfully');

        const request = new sql.Request();

        await request.query(`
      IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='ProcessingHistory' AND xtype='U')
      CREATE TABLE ProcessingHistory (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Filename NVARCHAR(255) NOT NULL,
        BlobUrl NVARCHAR(500) NOT NULL,
        OcrResult NVARCHAR(MAX),
        ProcessedAt DATETIME2 DEFAULT GETDATE()
      )
    `);

        console.log('Database initialized successfully');
    } catch (err) {
        console.error('Database initialization error:', {
            message: err.message,
            code: err.code,
            number: err.number,
            state: err.state,
            class: err.class
        });
    }
}

// Endpoint pentru upload si procesare imagine
app.post('/api/process-image', upload.single('image'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'No file uploaded' });
        }

        const file = req.file;
        const blobName = `${Date.now()}-${file.originalname}`;

        console.log(`Processing file: ${file.originalname}`);

        // 1. Upload la Azure Blob Storage
        if (!blobServiceClient) {
            throw new Error('Blob Storage client not initialized');
        }

        const containerClient = blobServiceClient.getContainerClient(azureConfig.containerName);
        await containerClient.createIfNotExists({ access: 'blob' });

        const blockBlobClient = containerClient.getBlockBlobClient(blobName);
        const uploadResponse = await blockBlobClient.uploadFile(file.path);

        const blobUrl = blockBlobClient.url;
        console.log(`File uploaded to Azure Blob Storage: ${blobUrl}`);

        // 2. Procesare OCR cu Azure Computer Vision
        let extractedText = '';
        try {
            if (!computerVisionClient) {
                throw new Error('Computer Vision client not initialized');
            }

            const ocrResult = await computerVisionClient.recognizePrintedText(false, blobUrl);

            // Proceseaza rezultatul OCR pentru a extrage textul
            if (ocrResult.regions) {
                ocrResult.regions.forEach(region => {
                    region.lines.forEach(line => {
                        line.words.forEach(word => {
                            extractedText += word.text + ' ';
                        });
                        extractedText += '\n';
                    });
                });
            }

            if (!extractedText.trim()) {
                extractedText = 'No text detected in the image';
            }
        } catch (ocrError) {
            console.error('OCR Error:', ocrError.message);
            extractedText = `OCR processing failed: ${ocrError.message}`;
        }

        // 3. Salveaza in Azure SQL Database
        try {
            await sql.connect(sqlConfig);
            const request = new sql.Request();

            await request
                .input('filename', sql.NVarChar, file.originalname)
                .input('blobUrl', sql.NVarChar, blobUrl)
                .input('ocrResult', sql.NVarChar, extractedText.trim())
                .query('INSERT INTO ProcessingHistory (Filename, BlobUrl, OcrResult) VALUES (@filename, @blobUrl, @ocrResult)');

            console.log('Record saved to database');
        } catch (dbError) {
            console.error('Database save error:', dbError.message);
            // Nu opreste procesarea pentru erori de baza de date
        }

        // 4. sterge fisierul temporar
        fs.unlinkSync(file.path);

        // 5. Returneaza rezultatul
        res.json({
            success: true,
            filename: file.originalname,
            blobUrl: blobUrl,
            ocrResult: extractedText.trim(),
            processedAt: new Date().toISOString()
        });

    } catch (error) {
        console.error('Error processing image:', error);
        res.status(500).json({
            error: 'Failed to process image',
            details: error.message
        });

        // sterge fisierul temporar in caz de eroare
        if (req.file && fs.existsSync(req.file.path)) {
            fs.unlinkSync(req.file.path);
        }
    }
});

// Endpoint pentru obtinerea istoricului
app.get('/api/history', async (req, res) => {
    try {
        await sql.connect(sqlConfig);
        const request = new sql.Request();

        const result = await request.query('SELECT * FROM ProcessingHistory ORDER BY ProcessedAt DESC');

        res.json({
            success: true,
            history: result.recordset
        });
    } catch (error) {
        console.error('Error fetching history:', error);
        res.status(500).json({
            error: 'Failed to fetch history',
            details: error.message
        });
    }
});

// Endpoint pentru obtinerea unui rezultat specific
app.get('/api/result/:id', async (req, res) => {
    try {
        const { id } = req.params;

        await sql.connect(sqlConfig);
        const request = new sql.Request();

        const result = await request
            .input('id', sql.Int, id)
            .query('SELECT * FROM ProcessingHistory WHERE Id = @id');

        if (result.recordset.length === 0) {
            return res.status(404).json({ error: 'Result not found' });
        }

        res.json({
            success: true,
            result: result.recordset[0]
        });
    } catch (error) {
        console.error('Error fetching result:', error);
        res.status(500).json({
            error: 'Failed to fetch result',
            details: error.message
        });
    }
});

// Endpoint de health check
app.get('/api/health', (req, res) => {
    res.json({
        status: 'OK',
        timestamp: new Date().toISOString(),
        services: {
            blobStorage: !!blobServiceClient,
            computerVision: !!computerVisionClient,
            database: !!sqlConfig
        }
    });
});

// Endpoint pentru debugging (fara informatii sensibile)
app.get('/api/debug', (req, res) => {
    res.json({
        environment: {
            hasStorageConnectionString: !!process.env.AZURE_STORAGE_CONNECTION_STRING,
            hasOcrApiKey: !!process.env.AZURE_OCR_API_KEY,
            hasSqlConnectionString: !!process.env.AZURE_SQL_CONNECTION_STRING,
            ocrEndpoint: process.env.AZURE_OCR_ENDPOINT,
            containerName: process.env.AZURE_CONTAINER_NAME
        },
        services: {
            blobServiceClient: !!blobServiceClient,
            computerVisionClient: !!computerVisionClient,
            sqlConfig: !!sqlConfig
        },
        sqlConfig: sqlConfig ? {
            server: sqlConfig.server,
            database: sqlConfig.database,
            user: sqlConfig.user,
            port: sqlConfig.port,
            passwordLength: sqlConfig.password?.length,
            passwordFirst3Chars: sqlConfig.password?.substring(0, 3),
            passwordLast3Chars: sqlConfig.password?.substring(sqlConfig.password.length - 3)
        } : null
    });
});

// Initializeaza baza de date la pornire
initializeDatabase();

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
    console.log(`AI Backend server running on port ${PORT}`);
});