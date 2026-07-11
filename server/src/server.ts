import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { config as loadEnv } from 'dotenv';
import { registerTools } from './tools/register.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
loadEnv({ path: resolve(__dirname, '../.env'), quiet: true });

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing ${key} in environment. See .env.example.`);
  return v;
}

async function main(): Promise<void> {
  const transport = (process.env.MCP_TRANSPORT ?? 'stdio').toLowerCase();

  if (transport === 'http') {
    const { startHttpServer } = await import('./server-http.js');
    await startHttpServer({ authToken: requireEnv('MCP_AUTH_TOKEN') });
    return;
  }

  const server = new McpServer({ name: 'gains', version: '0.1.0' });
  registerTools(server);
  await server.connect(new StdioServerTransport());
}

main().catch((err) => {
  console.error('[gains] fatal:', err);
  process.exit(1);
});
