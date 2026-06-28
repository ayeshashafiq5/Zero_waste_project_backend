require('dotenv').config();

// Fail fast — crash immediately if critical env vars are absent rather than
// letting the server start and die on the first database call.
const REQUIRED_ENV = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'];
const missing = REQUIRED_ENV.filter((k) => !process.env[k]);
if (missing.length) {
  // eslint-disable-next-line no-console
  console.error(`[server] Missing required environment variables: ${missing.join(', ')}`);
  process.exit(1);
}

const app = require('./src/app');

const PORT = process.env.PORT || 5000;

const server = app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`[server] zero-waste-backend listening on :${PORT} (${process.env.NODE_ENV || 'development'})`);
});

const shutdown = (signal) => {
  // eslint-disable-next-line no-console
  console.log(`[server] received ${signal}, closing gracefully…`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10_000).unref();
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
