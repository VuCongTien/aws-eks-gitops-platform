const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');
const { AppConfigDataClient, StartConfigurationSessionCommand, GetLatestConfigurationCommand } = require('@aws-sdk/client-appconfigdata');

require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

// Environment variables provided by Kubernetes Downward API & ConfigMaps
const podName = process.env.POD_NAME || process.env.HOSTNAME || 'local-pod-' + Math.random().toString(36).substring(7);
const nodeName = process.env.NODE_NAME || 'local-node-1';
const podNamespace = process.env.POD_NAMESPACE || 'production';
const nodeAZ = process.env.NODE_AZ || process.env.AWS_AVAILABILITY_ZONE || 'ap-southeast-1a';
const awsRegion = process.env.AWS_REGION || 'ap-southeast-1';

// Cache for AWS Secrets & AppConfig
let dbSecretsCache = null;
let appConfigCache = { message: 'Default internal app config', version: '1.0.0' };
let dbPool = null;

// Initialize AWS Clients (Uses IRSA - IAM Roles for Service Accounts)
const secretsClient = new SecretsManagerClient({ region: awsRegion });
const appConfigClient = new AppConfigDataClient({ region: awsRegion });

/**
 * Fetch Secrets from AWS Secrets Manager using IRSA
 */
async function getDatabaseSecrets() {
  const secretName = process.env.SECRET_NAME || 'prod/rds/postgres';

  // Fallback to explicit env vars if provided directly
  if (process.env.DB_HOST && process.env.DB_PASSWORD) {
    return {
      host: process.env.DB_HOST,
      port: parseInt(process.env.DB_PORT || '5432', 10),
      username: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD,
      dbname: process.env.DB_NAME || 'appdb',
      source: 'Environment Variables'
    };
  }

  if (dbSecretsCache) {
    return dbSecretsCache;
  }

  try {
    const command = new GetSecretValueCommand({ SecretId: secretName });
    const response = await secretsClient.send(command);
    if (response.SecretString) {
      const secret = JSON.parse(response.SecretString);
      dbSecretsCache = {
        host: secret.host || secret.hostname,
        port: parseInt(secret.port || '5432', 10),
        username: secret.username || secret.user,
        password: secret.password,
        dbname: secret.dbname || secret.database || 'appdb',
        source: `AWS Secrets Manager (${secretName})`
      };
      return dbSecretsCache;
    }
  } catch (error) {
    console.warn(`[SecretsManager] Could not fetch secret '${secretName}':`, error.message);
    return null;
  }
  return null;
}

/**
 * Initialize PostgreSQL Database Connection Pool
 */
async function initDbPool() {
  if (dbPool) return dbPool;

  const secrets = await getDatabaseSecrets();
  if (!secrets || !secrets.host) {
    console.log('[Database] Secrets not available or DB host omitted. Database features will run in mock mode.');
    return null;
  }

  try {
    dbPool = new Pool({
      host: secrets.host,
      port: secrets.port,
      user: secrets.username,
      password: secrets.password,
      database: secrets.dbname,
      connectionTimeoutMillis: 3000,
      ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
    });

    // Auto-create visits table if connected
    const client = await dbPool.connect();
    await client.query(`
      CREATE TABLE IF NOT EXISTS page_visits (
        id SERIAL PRIMARY KEY,
        pod_name VARCHAR(100) NOT NULL,
        node_az VARCHAR(50) NOT NULL,
        visited_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );
    `);
    client.release();
    console.log('[Database] Successfully connected to PostgreSQL and ensured schema!');
    return dbPool;
  } catch (error) {
    console.error('[Database] Connection failed:', error.message);
    dbPool = null;
    return null;
  }
}

/**
 * Fetch configuration from AWS AppConfig
 */
async function fetchAppConfig() {
  const appId = process.env.APPCONFIG_APPLICATION;
  const envId = process.env.APPCONFIG_ENVIRONMENT;
  const profileId = process.env.APPCONFIG_PROFILE;

  if (!appId || !envId || !profileId) {
    return { status: 'Not Configured', data: appConfigCache };
  }

  try {
    const sessionCmd = new StartConfigurationSessionCommand({
      ApplicationIdentifier: appId,
      EnvironmentIdentifier: envId,
      ConfigurationProfileIdentifier: profileId,
    });
    const session = await appConfigClient.send(sessionCmd);

    const configCmd = new GetLatestConfigurationCommand({
      ConfigurationToken: session.InitialConfigurationToken,
    });
    const configResp = await appConfigClient.send(configCmd);
    if (configResp.Configuration) {
      const str = Buffer.from(configResp.Configuration).toString('utf-8');
      appConfigCache = JSON.parse(str);
      return { status: 'Connected (AWS AppConfig)', data: appConfigCache };
    }
  } catch (error) {
    console.warn('[AppConfig] Error fetching config:', error.message);
    return { status: 'Error: ' + error.message, data: appConfigCache };
  }

  return { status: 'Active (Cached)', data: appConfigCache };
}

// ----------------------------------------------------
// ROUTES
// ----------------------------------------------------

// Health Check Endpoint (K8s Liveness & Readiness Probe)
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'UP', timestamp: new Date().toISOString() });
});

// Pod & System Topology Info Endpoint
app.get('/api/info', async (req, res) => {
  const secrets = await getDatabaseSecrets();
  const appConfigResult = await fetchAppConfig();

  res.json({
    podName,
    nodeName,
    namespace: podNamespace,
    az: nodeAZ,
    region: awsRegion,
    timestamp: new Date().toISOString(),
    security: {
      authMode: 'IAM Role for Service Accounts (IRSA)',
      secretsManager: secrets ? {
        status: 'Connected',
        source: secrets.source,
        dbHost: secrets.host,
        dbUser: secrets.username,
        dbName: secrets.dbname
      } : {
        status: 'Not Connected / Using Environment Vars',
        source: 'None'
      },
      appConfig: appConfigResult
    }
  });
});

// Database Visits Endpoint - Read History
app.get('/api/db/visits', async (req, res) => {
  const pool = await initDbPool();
  
  if (!pool) {
    return res.json({
      dbStatus: 'Disconnected / Mock Mode',
      totalVisits: 0,
      recentVisits: [
        { id: 1, pod_name: podName, node_az: nodeAZ, visited_at: new Date().toISOString() }
      ],
      message: 'PostgreSQL database is currently offline or unreachable from this network.'
    });
  }

  try {
    const countRes = await pool.query('SELECT COUNT(*) FROM page_visits');
    const recentRes = await pool.query('SELECT * FROM page_visits ORDER BY id DESC LIMIT 10');

    res.json({
      dbStatus: 'Connected (RDS PostgreSQL)',
      totalVisits: parseInt(countRes.rows[0].count, 10),
      recentVisits: recentRes.rows
    });
  } catch (error) {
    res.status(500).json({
      dbStatus: 'Error',
      error: error.message
    });
  }
});

// Database Visits Endpoint - Log a new visit
app.post('/api/db/visit', async (req, res) => {
  const pool = await initDbPool();

  if (!pool) {
    return res.json({
      success: false,
      message: 'Database not connected. Visit recorded in mock mode only.',
      recorded: { pod_name: podName, node_az: nodeAZ, visited_at: new Date().toISOString() }
    });
  }

  try {
    const insertRes = await pool.query(
      'INSERT INTO page_visits (pod_name, node_az) VALUES ($1, $2) RETURNING *',
      [podName, nodeAZ]
    );

    res.json({
      success: true,
      message: 'Recorded visit to RDS PostgreSQL!',
      recorded: insertRes.rows[0]
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// CPU Stress Endpoint to test Autoscaling (HPA)
app.all('/api/stress', (req, res) => {
  const durationSeconds = parseInt(req.query.seconds || req.body?.seconds || '10', 10);
  const cappedDuration = Math.min(Math.max(durationSeconds, 1), 60); // Cap between 1s and 60s

  console.log(`[Stress Test] Starting CPU stress on Pod ${podName} for ${cappedDuration} seconds...`);
  
  const startTime = Date.now();
  let iterations = 0;

  // Intensive CPU calculation loop (calculating primes / math operations)
  while ((Date.now() - startTime) < cappedDuration * 1000) {
    for (let i = 0; i < 100000; i++) {
      Math.sqrt(Math.random() * Math.random() * 99999);
    }
    iterations++;
  }

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(2);
  console.log(`[Stress Test] Completed CPU stress on Pod ${podName}. Duration: ${elapsed}s, Iterations: ${iterations}`);

  res.json({
    message: `CPU load generated successfully on Pod ${podName}`,
    podName,
    nodeAZ,
    durationRequestedSeconds: cappedDuration,
    actualDurationSeconds: parseFloat(elapsed),
    iterationsCompleted: iterations,
    hpaNotice: 'If HPA threshold (e.g., CPU > 50%) is met, Kubernetes will scale out new pods.'
  });
});

// Start Server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`=======================================================`);
  console.log(`🚀 EKS Production Lab Backend Service running on port ${PORT}`);
  console.log(`📌 Pod Name: ${podName}`);
  console.log(`📌 Node Name: ${nodeName}`);
  console.log(`📌 Node AZ: ${nodeAZ}`);
  console.log(`📌 Namespace: ${podNamespace}`);
  console.log(`=======================================================`);
});
