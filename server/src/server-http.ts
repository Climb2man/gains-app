import { createHmac, randomUUID } from 'node:crypto';
import { requireBearerAuth } from '@modelcontextprotocol/sdk/server/auth/middleware/bearerAuth.js';
import { mcpAuthRouter } from '@modelcontextprotocol/sdk/server/auth/router.js';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import express, { type Request, type Response } from 'express';
import {
  GainsOAuthProvider,
  renderConsentForm,
  setConsentSecurityHeaders,
} from './oauth_provider.js';
import { HealthSlice } from './slice.js';
import { store } from './store.js';
import { registerTools } from './tools/register.js';

export interface HttpServerOptions {
  /** Bearer token clients must present + JWT signing secret. Required, ≥16 chars. */
  authToken: string;
  port?: number;
  host?: string;
}

export async function startHttpServer(opts: HttpServerOptions): Promise<void> {
  if (!opts.authToken || opts.authToken.length < 16) {
    throw new Error(
      'MCP_AUTH_TOKEN must be set and at least 16 chars. Generate one with `openssl rand -hex 32`.',
    );
  }
  const port = opts.port ?? Number(process.env.PORT ?? 3000);
  const host = opts.host ?? '0.0.0.0';
  const password = process.env.AUTH_PASSWORD ?? '';
  const publicUrl = process.env.PUBLIC_URL || `http://localhost:${port}`;
  const oauthEnabled = password.length > 0;
  const resourceUrl = `${publicUrl.replace(/\/$/, '')}/mcp`;
  const signingSecret = createHmac('sha256', opts.authToken)
    .update('gains/oauth-jwt-signing/v1')
    .digest('hex');

  const provider = new GainsOAuthProvider({
    signingSecret,
    password,
    staticToken: opts.authToken,
    resourceUrl,
  });

  const sessions = new Map<
    string,
    { server: McpServer; transport: StreamableHTTPServerTransport }
  >();

  /** Thrown when a client presents an mcp-session-id the server no longer knows about. */
  class UnknownSessionError extends Error {}

  async function getOrCreateSession(
    existingSessionId: string | undefined,
  ): Promise<{ server: McpServer; transport: StreamableHTTPServerTransport }> {
    if (existingSessionId) {
      const existing = sessions.get(existingSessionId);
      if (existing) return existing;
      // An UNRECOGNISED id must not silently mint a fresh session. The client keeps sending the id it
      // already has, so every retry used to allocate another McpServer + transport that nothing could
      // ever reach: the only cleanup path is transport.onclose, which needs a DELETE that validation
      // rejects on an uninitialised session. The map grew without bound. Per the Streamable HTTP spec
      // the answer is 404, which is also the only signal that tells a client to re-initialize (after a
      // redeploy, say) rather than retry forever.
      throw new UnknownSessionError(existingSessionId);
    }
    const newId = randomUUID();
    const newServer = new McpServer({ name: 'gains', version: '0.1.0' });
    registerTools(newServer);
    const newTransport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => newId,
      enableJsonResponse: true,
    });
    newTransport.onclose = (): void => {
      sessions.delete(newId);
    };
    await newServer.connect(newTransport as Parameters<typeof newServer.connect>[0]);
    const entry = { server: newServer, transport: newTransport };
    sessions.set(newId, entry);
    return entry;
  }

  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 1);

  app.use((req, res, next) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type, mcp-session-id');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
    res.setHeader('Access-Control-Expose-Headers', 'mcp-session-id, www-authenticate');
    if (req.method === 'OPTIONS') {
      res.status(204).end();
      return;
    }
    next();
  });

  // Registered BEFORE the auth router, so anything returned here is world-readable and the
  // Access-Control-Allow-Origin: '*' above makes it readable from any web page too. `store.status()`
  // exposes sync timestamps and per-domain day counts, which describe the owner's logging habits.
  // The Dockerfile healthcheck only needs a 200, so it gets one and nothing else.
  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  const issuerUrl = new URL(publicUrl);
  const resourceServerUrl = new URL(resourceUrl);
  app.use(mcpAuthRouter({ provider, issuerUrl, resourceServerUrl }));

  const consentHits = new Map<string, { count: number; resetAt: number }>();
  const CONSENT_MAX = 10;
  const CONSENT_WINDOW_MS = 15 * 60 * 1000;
  let globalFails = 0;
  let globalResetAt = 0;
  const GLOBAL_FAIL_MAX = 50;

  app.post(
    '/oauth/consent',
    express.urlencoded({ extended: false }),
    (req: Request, res: Response) => {
      if (!oauthEnabled) {
        res.status(403).json({
          error: 'oauth_disabled',
          error_description: 'AUTH_PASSWORD is not set on this server.',
        });
        return;
      }
      const ip = req.ip ?? 'unknown';
      const now = Date.now();
      if (now > globalResetAt) {
        globalFails = 0;
        globalResetAt = now + CONSENT_WINDOW_MS;
      }
      if (globalFails >= GLOBAL_FAIL_MAX) {
        res.status(429).json({
          error: 'too_many_requests',
          error_description: 'Too many failed attempts. Wait 15 minutes.',
        });
        return;
      }
      const hit = consentHits.get(ip);
      if (!hit || now > hit.resetAt) {
        consentHits.set(ip, { count: 1, resetAt: now + CONSENT_WINDOW_MS });
      } else if (++hit.count > CONSENT_MAX) {
        res.status(429).json({
          error: 'too_many_requests',
          error_description: 'Too many attempts. Wait 15 minutes.',
        });
        return;
      }
      const body = req.body as Record<string, string>;
      const redirect = provider.consent({
        clientId: body.client_id ?? '',
        redirectUri: body.redirect_uri ?? '',
        codeChallenge: body.code_challenge ?? '',
        state: body.state ?? '',
        scopes: body.scope ?? '',
        resource: body.resource ?? '',
        password: body.password ?? '',
      });
      if (!redirect) {
        globalFails++;
        setConsentSecurityHeaders(res);
        res.status(401).setHeader('content-type', 'text/html; charset=utf-8');
        res.end(
          renderConsentForm({
            clientId: body.client_id ?? '',
            redirectUri: body.redirect_uri ?? '',
            codeChallenge: body.code_challenge ?? '',
            state: body.state ?? '',
            scopes: body.scope ?? '',
            resource: body.resource ?? '',
            error: true,
          }),
        );
        return;
      }
      res.redirect(302, redirect);
    },
  );

  const bearer = requireBearerAuth({
    verifier: provider,
    resourceMetadataUrl: `${publicUrl.replace(/\/$/, '')}/.well-known/oauth-protected-resource/mcp`,
  });

  app.post('/sync', bearer, express.json({ limit: '5mb' }), (req: Request, res: Response) => {
    if (req.auth?.clientId !== 'static') {
      res.status(403).json({
        error: 'forbidden',
        error_description: 'Only the phone (static bearer) may push data.',
      });
      return;
    }
    const parsed = HealthSlice.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: 'invalid_slice', issues: parsed.error.issues.slice(0, 10) });
      return;
    }
    store.set(parsed.data);
    res.json({ ok: true, status: store.status() });
  });

  app.delete('/sync', bearer, (req: Request, res: Response) => {
    if (req.auth?.clientId !== 'static') {
      res.status(403).json({ error: 'forbidden' });
      return;
    }
    store.clear();
    res.json({ ok: true });
  });

  const mcpHandler = async (req: Request, res: Response): Promise<void> => {
    try {
      const sessionIdHeader = req.headers['mcp-session-id'];
      const sid = typeof sessionIdHeader === 'string' ? sessionIdHeader : undefined;
      const session = await getOrCreateSession(sid);
      await session.transport.handleRequest(req, res, req.body);
    } catch (err) {
      if (err instanceof UnknownSessionError) {
        if (!res.headersSent) res.status(404).json({ error: 'unknown session; re-initialize' });
        return;
      }
      console.error('[gains] request error:', err);
      if (!res.headersSent) res.status(500).json({ error: 'internal server error' });
    }
  };

  app.post('/mcp', bearer, express.json(), (req, res) => void mcpHandler(req, res));
  app.get('/mcp', bearer, (req, res) => void mcpHandler(req, res));
  app.delete('/mcp', bearer, (req, res) => void mcpHandler(req, res));

  const httpServer = app.listen(port, host, () => {
    console.error(`[gains] listening on ${publicUrl} (bound ${host}:${port})`);
    console.error(`[gains] health: GET /health · sync: POST /sync`);
    console.error(
      `[gains] auth: static bearer (MCP_AUTH_TOKEN)${oauthEnabled ? ' + OAuth (web/mobile connectors)' : ': OAuth disabled (set AUTH_PASSWORD to enable)'}`,
    );
  });

  const close = (): void => {
    httpServer.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 5000).unref();
  };
  process.on('SIGINT', close);
  process.on('SIGTERM', close);
}
