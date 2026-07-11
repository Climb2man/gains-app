import { createHmac, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import type { OAuthRegisteredClientsStore } from '@modelcontextprotocol/sdk/server/auth/clients.js';
import { InvalidTokenError } from '@modelcontextprotocol/sdk/server/auth/errors.js';
import type {
  AuthorizationParams,
  OAuthServerProvider,
} from '@modelcontextprotocol/sdk/server/auth/provider.js';
import type { AuthInfo } from '@modelcontextprotocol/sdk/server/auth/types.js';
import type {
  OAuthClientInformationFull,
  OAuthTokens,
} from '@modelcontextprotocol/sdk/shared/auth.js';
import type { Response } from 'express';

const ACCESS_TTL_S = 3600;
const REFRESH_TTL_S = 30 * 24 * 3600;
const CODE_TTL_MS = 60_000;

function b64url(buf: Buffer): string {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64urlDecode(s: string): Buffer {
  return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}
function signToken(payload: Record<string, unknown>, secret: string): string {
  const header = b64url(Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const body = b64url(Buffer.from(JSON.stringify(payload)));
  const data = `${header}.${body}`;
  const sig = b64url(createHmac('sha256', secret).update(data).digest());
  return `${data}.${sig}`;
}
function verifyToken(token: string, secret: string): Record<string, unknown> | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [h, b, s] = parts as [string, string, string];
  const expected = b64url(createHmac('sha256', secret).update(`${h}.${b}`).digest());
  const sBuf = Buffer.from(s);
  const eBuf = Buffer.from(expected);
  if (sBuf.length !== eBuf.length || !timingSafeEqual(sBuf, eBuf)) return null;
  try {
    const payload = JSON.parse(b64urlDecode(b).toString('utf8')) as Record<string, unknown>;
    if (typeof payload.exp === 'number' && Date.now() / 1000 > payload.exp) return null;
    return payload;
  } catch {
    return null;
  }
}

function constantTimeEqual(a: string, b: string): boolean {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  return ba.length === bb.length && timingSafeEqual(ba, bb);
}

interface AuthCodeEntry {
  challenge: string;
  redirectUri: string;
  clientId: string;
  scopes: string[];
  resource: string | undefined;
  expiresAt: number;
}

export interface GainsOAuthOptions {
  /** Secret used to sign JWT tokens + client IDs. */
  signingSecret: string;
  /** Password the user enters at /authorize. */
  password: string;
  /** Static bearer token (MCP_AUTH_TOKEN), accepted directly without the OAuth flow. */
  staticToken: string;
  /** MCP resource URL (…/mcp) for RFC 8707 audience binding; log-only, not enforced. */
  resourceUrl?: string;
}

export class GainsOAuthProvider implements OAuthServerProvider {
  private readonly codes = new Map<string, AuthCodeEntry>();
  private readonly signingSecret: string;
  private readonly password: string;
  private readonly staticToken: string;
  private readonly resourceUrl: string | undefined;

  constructor(opts: GainsOAuthOptions) {
    this.signingSecret = opts.signingSecret;
    this.password = opts.password;
    this.staticToken = opts.staticToken;
    this.resourceUrl = opts.resourceUrl;
  }

  private decodeClient(clientId: string): OAuthClientInformationFull | undefined {
    if (!clientId.startsWith('c.')) return undefined;
    const payload = verifyToken(clientId.slice(2), this.signingSecret);
    if (!payload || payload.t !== 'client') return undefined;
    return {
      client_id: clientId,
      redirect_uris: (payload.ru as string[]) ?? [],
      token_endpoint_auth_method: 'none',
      grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'],
      scope: (payload.sc as string) ?? '',
    } as OAuthClientInformationFull;
  }

  get clientsStore(): OAuthRegisteredClientsStore {
    return {
      getClient: (clientId: string): OAuthClientInformationFull | undefined =>
        this.decodeClient(clientId),
      registerClient: (
        client: Omit<OAuthClientInformationFull, 'client_id' | 'client_id_issued_at'>,
      ): OAuthClientInformationFull => {
        const signed = signToken(
          {
            t: 'client',
            ru: client.redirect_uris ?? [],
            sc: client.scope ?? '',
            jti: randomUUID(),
          },
          this.signingSecret,
        );
        const clientId = `c.${signed}`;
        return {
          ...client,
          client_id: clientId,
          client_id_issued_at: Math.floor(Date.now() / 1000),
        } as OAuthClientInformationFull;
      },
    };
  }

  async authorize(
    client: OAuthClientInformationFull,
    params: AuthorizationParams,
    res: Response,
  ): Promise<void> {
    setConsentSecurityHeaders(res);
    res.setHeader('content-type', 'text/html; charset=utf-8');
    res.setHeader('cache-control', 'no-store');
    res.end(
      renderConsentForm({
        clientId: client.client_id,
        redirectUri: params.redirectUri,
        codeChallenge: params.codeChallenge,
        state: params.state ?? '',
        scopes: (params.scopes ?? []).join(' '),
        resource: params.resource?.toString() ?? '',
        error: false,
      }),
    );
  }

  consent(input: {
    clientId: string;
    redirectUri: string;
    codeChallenge: string;
    state: string;
    scopes: string;
    resource: string;
    password: string;
  }): string | null {
    if (!constantTimeEqual(input.password, this.password)) {
      console.error('[gains] consent REJECTED: password mismatch');
      return null;
    }
    const client = this.decodeClient(input.clientId);
    if (!client) {
      console.error(
        '[gains] consent REJECTED: client_id failed to decode (stale registration / signing-key mismatch). Password was correct',
      );
      return null;
    }
    if (!client.redirect_uris.includes(input.redirectUri)) {
      console.error(
        `[gains] consent REJECTED: redirect_uri not registered: ${input.redirectUri}. Password was correct`,
      );
      return null;
    }

    const code = b64url(randomBytes(32));
    this.codes.set(code, {
      challenge: input.codeChallenge,
      redirectUri: input.redirectUri,
      clientId: input.clientId,
      scopes: input.scopes ? input.scopes.split(' ').filter(Boolean) : [],
      resource: input.resource || undefined,
      expiresAt: Date.now() + CODE_TTL_MS,
    });

    const url = new URL(input.redirectUri);
    url.searchParams.set('code', code);
    if (input.state) url.searchParams.set('state', input.state);
    return url.toString();
  }

  async challengeForAuthorizationCode(
    client: OAuthClientInformationFull,
    authorizationCode: string,
  ): Promise<string> {
    const entry = this.codes.get(authorizationCode);
    if (!entry || entry.expiresAt < Date.now() || entry.clientId !== client.client_id) {
      throw new Error('invalid or expired authorization code');
    }
    return entry.challenge;
  }

  async exchangeAuthorizationCode(
    client: OAuthClientInformationFull,
    authorizationCode: string,
  ): Promise<OAuthTokens> {
    const entry = this.codes.get(authorizationCode);
    if (!entry || entry.expiresAt < Date.now() || entry.clientId !== client.client_id) {
      throw new Error('invalid or expired authorization code');
    }
    this.codes.delete(authorizationCode);
    return this.issueTokens(client.client_id, entry.scopes, entry.resource);
  }

  async exchangeRefreshToken(
    client: OAuthClientInformationFull,
    refreshToken: string,
    scopes?: string[],
  ): Promise<OAuthTokens> {
    const payload = verifyToken(refreshToken, this.signingSecret);
    if (!payload || payload.typ !== 'refresh' || payload.cid !== client.client_id) {
      throw new Error('invalid refresh token');
    }
    const grantScopes = scopes ?? (payload.scopes as string[]) ?? [];
    return this.issueTokens(client.client_id, grantScopes, payload.resource as string | undefined);
  }

  private issueTokens(
    clientId: string,
    scopes: string[],
    resource: string | undefined,
  ): OAuthTokens {
    const now = Math.floor(Date.now() / 1000);
    const base = { cid: clientId, scopes, resource, iat: now };
    const access = signToken(
      { ...base, typ: 'access', exp: now + ACCESS_TTL_S },
      this.signingSecret,
    );
    const refresh = signToken(
      { ...base, typ: 'refresh', exp: now + REFRESH_TTL_S },
      this.signingSecret,
    );
    return {
      access_token: access,
      token_type: 'Bearer',
      expires_in: ACCESS_TTL_S,
      refresh_token: refresh,
      scope: scopes.join(' '),
    };
  }

  async verifyAccessToken(token: string): Promise<AuthInfo> {
    if (this.staticToken && constantTimeEqual(token, this.staticToken)) {
      return {
        token,
        clientId: 'static',
        scopes: [],
        expiresAt: Math.floor(Date.now() / 1000) + REFRESH_TTL_S,
      };
    }
    const payload = verifyToken(token, this.signingSecret);
    if (payload && payload.typ === 'access') {
      if (this.resourceUrl && typeof payload.resource === 'string') {
        const norm = (u: string): string => u.replace(/\/+$/, '');
        if (norm(payload.resource) !== norm(this.resourceUrl)) {
          console.error(
            `[gains] token resource mismatch (got "${payload.resource}", expected "${this.resourceUrl}"), allowing; enforcement disabled`,
          );
        }
      }
      const info: AuthInfo = {
        token,
        clientId: String(payload.cid),
        scopes: (payload.scopes as string[]) ?? [],
        expiresAt: payload.exp as number,
      };
      if (typeof payload.resource === 'string') info.resource = new URL(payload.resource);
      return info;
    }
    throw new InvalidTokenError('invalid or expired access token');
  }
}

export function setConsentSecurityHeaders(res: Response): void {
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
}

export function renderConsentForm(d: {
  clientId: string;
  redirectUri: string;
  codeChallenge: string;
  state: string;
  scopes: string;
  resource: string;
  error: boolean;
}): string {
  const esc = (s: string): string =>
    s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const errorBanner = d.error
    ? `<p style="color:#dc2626;margin:0 0 16px">Incorrect password. Try again.</p>`
    : '';
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Gains · authorize</title>
<style>
  body { font-family: -apple-system, ui-sans-serif, system-ui, sans-serif; background: #0d1117; color: #e6e6e6;
         display: flex; min-height: 100vh; align-items: center; justify-content: center; margin: 0; }
  .card { background: #161b22; border: 1px solid #30363d; border-radius: 14px; padding: 32px;
          width: 320px; box-shadow: 0 8px 32px rgba(0,0,0,.4); }
  h1 { font-size: 18px; margin: 0 0 4px; }
  p.sub { color: #969696; font-size: 13px; margin: 0 0 24px; }
  label { display: block; font-size: 13px; margin: 0 0 8px; color: #b0b0b0; }
  input[type=password] { width: 100%; box-sizing: border-box; padding: 10px 12px; border-radius: 8px;
         border: 1px solid #30363d; background: #0d1117; color: #e6e6e6; font-size: 14px; margin: 0 0 20px; }
  button { width: 100%; padding: 11px; border: none; border-radius: 8px; background: #e6e6e6; color: #0d1117;
           font-weight: 700; font-size: 14px; cursor: pointer; }
  button:hover { background: #fff; }
</style>
</head>
<body>
  <div class="card">
    <h1>Gains</h1>
    <p class="sub">Enter your access password to connect your personal health record to your assistant.</p>
    ${errorBanner}
    <form method="POST" action="/oauth/consent">
      <input type="hidden" name="client_id" value="${esc(d.clientId)}">
      <input type="hidden" name="redirect_uri" value="${esc(d.redirectUri)}">
      <input type="hidden" name="code_challenge" value="${esc(d.codeChallenge)}">
      <input type="hidden" name="state" value="${esc(d.state)}">
      <input type="hidden" name="scope" value="${esc(d.scopes)}">
      <input type="hidden" name="resource" value="${esc(d.resource)}">
      <label for="pw">Password</label>
      <input type="password" id="pw" name="password" autofocus autocomplete="current-password">
      <button type="submit">Authorize</button>
    </form>
  </div>
</body>
</html>`;
}
