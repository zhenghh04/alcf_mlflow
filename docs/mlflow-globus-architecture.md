# MLflow + Globus Auth Architecture

This diagram shows the public access and authentication flow for:

- `https://mlflow.alcf.anl.gov`
- `https://mlflow.alcf.anl.gov/oauth2/*`

```mermaid
flowchart LR
    U[User Browser]
    G[Globus Auth<br/>auth.globus.org]
    N[External Nginx<br/>mlflow.alcf.anl.gov]
    O[oauth2-proxy<br/>amsc-mlflow.alcf.anl.gov:8081]
    M[MLflow Server<br/>amsc-mlflow.alcf.anl.gov:8080]
    A[Email Allowlist<br/>huihuo.zheng@anl.gov<br/>venkat@anl.gov<br/>turam@anl.gov]

    U -->|HTTPS GET /| N
    N -->|auth_request /oauth2/auth| O
    O -->|401 unauthenticated| N
    N -->|302 /oauth2/sign_in| U
    U -->|/oauth2/start| N
    N -->|proxy /oauth2/*| O
    O -->|OIDC authorize| G
    G -->|callback /oauth2/callback| U
    U -->|/oauth2/callback| N
    N -->|proxy /oauth2/callback| O
    O -->|validate token + check email| A
    O -->|set session cookie| U
    U -->|retry GET / with cookie| N
    N -->|proxy authenticated request| M
    M -->|UI/API response| U
```

## Text Schematic (Fallback)

1. Browser requests `https://mlflow.alcf.anl.gov/`.
2. External nginx checks auth with `oauth2-proxy` via `/oauth2/auth`.
3. If unauthenticated, browser is redirected to Globus login.
4. Globus redirects back to `/oauth2/callback`.
5. `oauth2-proxy` validates callback and checks email allowlist.
6. If allowed, `oauth2-proxy` sets session cookie.
7. External nginx forwards authenticated traffic to MLflow on `:8080`.
