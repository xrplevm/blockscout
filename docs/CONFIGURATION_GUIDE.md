# Blockscout Configuration Guide for Custom Chains

This guide explains how to connect Blockscout to your own blockchain and customize all parameters.

## XRPL EVM Testnet Configuration

Blockscout is currently pre-configured for **XRPL EVM Testnet**.

### XRPL EVM Testnet Details

- **Chain ID**: `1449000` (0x161c28)
- **Native Currency**: XRP (18 decimals)
- **Public RPC Endpoint**: `https://rpc.testnet.xrplevm.org`
- **Full History RPC**: `https://full-history-bb325630.testnet.xrplevm.org`
- **WebSocket**: `wss://full-history-bb325630.testnet.xrplevm.org`
- **Official Explorer**: [explorer.testnet.xrplevm.org](https://explorer.testnet.xrplevm.org)
- **First Block**: `2162539`
- **Trace First Block**: `4900000`

### Pre-configured Endpoints (Testnet)

The configuration includes:
- **Primary RPC**: `https://rpc.testnet.xrplevm.org`
- **Fallback RPC / Full History**: `https://full-history-bb325630.testnet.xrplevm.org`
- **WebSocket**: `wss://full-history-bb325630.testnet.xrplevm.org`

---

## XRPL EVM Mainnet Configuration

To switch to **XRPL EVM Mainnet**, replace the testnet values with the mainnet ones below.

### XRPL EVM Mainnet Details

- **Chain ID**: `1440000` (0x15f900)
- **Cosmos Chain ID**: `xrplevm_1440000-1`
- **Native Currency**: XRP (18 decimals)
- **Official RPC Endpoint**: `https://rpc.xrplevm.org`
- **Official WebSocket**: `wss://ws.xrplevm.org`
- **Official Explorer**: [explorer.xrplevm.org](https://explorer.xrplevm.org)

### Pre-configured Endpoints (Mainnet)

- **Primary RPC**: `https://rpc.xrplevm.org` (Peersyst)
- **Fallback RPC**: `https://xrplevm.buildintheshade.com` (Grove)
- **WebSocket**: `wss://ws.xrplevm.org`
- **Fallback WebSocket**: `wss://xrplevm.buildintheshade.com`

### Additional RPC Providers (Mainnet)

As per [XRPL EVM Public APIs](https://docs.xrplevm.org/pages/developers/resources/public-apis), you can also use:
- **Pocket Network**: `https://api.pocket.network/docs/xrplevm`
- **Cumulo**: `https://json-rpc.xrpl.cumulo.org.es`
- **Imperator**: `https://rpc_evm-xrp.imperator.co/`
- **Enigma**: `https://xrp-evm-rpc.enigma-validator.com/`
- **Stakeme**: `https://xrpl-evm-rpc.stakeme.pro/`

## Quick Start

1. **Create the local `.env` file** (one-time setup to avoid volume permission issues):
   ```bash
   echo "UID=$(id -u)\nGID=$(id -g)" > docker-compose/.env
   ```
   This makes the backend container run as your host user so it can write to mounted volumes (`dets/`, `logs/`) without requiring `sudo`.

2. **Edit Backend Configuration**: `docker-compose/envs/common-blockscout.env`
3. **Edit Frontend Configuration**: `docker-compose/envs/common-frontend.env`
4. **Start the services**: `cd docker-compose && docker compose up -d`

## Production Deployment (GitHub Actions Image Build)

The docker-compose flow above is for local/manual setups. The actual deployment route used by the org is the GitHub Actions workflow:

- **Workflow**: `.github/workflows/publish-docker-image-for-xrplevm.yml`
- **Trigger**: manual (`workflow_dispatch`) with a `version` input (e.g. `0.0.0`)
- **Output**: builds `docker/Dockerfile` and pushes the multi-arch image (`linux/amd64`, `linux/arm64/v8`) to `ghcr.io/xrplevm/blockscout-xrplevm:<version>`

The `version` input is only the Docker image tag (and part of the displayed `BLOCKSCOUT_VERSION`) — it does not need to match anything else.

### The `RELEASE_VERSION` build arg (critical)

The `RELEASE_VERSION` build arg **must exactly match the `version` in `mix.exs`** (currently `11.2.2`). The Dockerfile uses it as a filesystem path — it copies `config_helper.exs` into `/app/releases/${RELEASE_VERSION}/`, and the Elixir release only reads from the directory named after the `mix.exs` version. A mismatched value produces an image that **builds successfully but crashes at boot** with an ENOENT error when it fails to find its release files.

The workflow derives `RELEASE_VERSION` from `mix.exs` automatically, so no manual input is needed for it. If you ever modify the workflow or build the image by hand (`docker build --build-arg RELEASE_VERSION=...`), make sure the value matches `mix.exs` — and remember to keep them in sync when bumping the Blockscout version during upstream merges.

## Essential Configuration Parameters

### 1. Backend Configuration (`docker-compose/envs/common-blockscout.env`)

#### **Chain Connection Settings** (REQUIRED)

```bash
# Your Ethereum JSON-RPC client type (geth, erigon, nethermind, openethereum, besu)
ETHEREUM_JSONRPC_VARIANT=geth

# Your chain's JSON-RPC HTTP endpoint
# For local node: http://host.docker.internal:8545/
# For remote node: http://your-node-ip:8545/
ETHEREUM_JSONRPC_HTTP_URL=http://host.docker.internal:8545/

# Trace endpoint (usually same as HTTP URL)
ETHEREUM_JSONRPC_TRACE_URL=http://host.docker.internal:8545/

# WebSocket endpoint (optional, for real-time updates)
ETHEREUM_JSONRPC_WS_URL=ws://host.docker.internal:8545/

# Transport method (http or ipc)
ETHEREUM_JSONRPC_TRANSPORT=http

# Chain ID of your blockchain
CHAIN_ID=1337
```

#### **Chain Identity Settings** (REQUIRED)

```bash
# Native coin name (e.g., "Ether", "XRP", "MyToken")
COIN_NAME=Your Coin Name

# Native coin symbol (e.g., "ETH", "XRP", "MYT")
COIN=YOUR_SYMBOL

# Chain type (optional, for specific chain optimizations)
# Options: xdai, poa, sokol, etc. Leave empty for generic EVM
CHAIN_TYPE=
```

#### **Network Configuration**

```bash
# Blockscout hostname (for API URLs)
BLOCKSCOUT_HOST=localhost

# Protocol (http or https)
BLOCKSCOUT_PROTOCOL=http

# Port for the backend API
PORT=4000

# Secret key base (generate a new one for production!)
# Generate with: mix phx.gen.secret
SECRET_KEY_BASE=your-secret-key-here
```

#### **Database Configuration**

```bash
# PostgreSQL connection string
DATABASE_URL=postgresql://blockscout:password@db:5432/blockscout

# Connection pool sizes
POOL_SIZE=80
POOL_SIZE_API=10
```

#### **Indexer Settings**

```bash
# Disable indexer if you only want API (not recommended)
# DISABLE_INDEXER=false

# First block to index (if starting from a specific block)
FIRST_BLOCK=0

# Last block to index (leave empty for no limit)
# LAST_BLOCK=

# Block ranges to process
# BLOCK_RANGES=
```

#### **Advanced RPC Configuration**

```bash
# Fallback RPC URLs (for redundancy)
# ETHEREUM_JSONRPC_FALLBACK_HTTP_URL=http://backup-node:8545/
# ETHEREUM_JSONRPC_FALLBACK_TRACE_URL=http://backup-node:8545/

# Multiple RPC URLs (load balancing)
# ETHEREUM_JSONRPC_HTTP_URLS=["http://node1:8545/","http://node2:8545/"]

# RPC timeout settings
# ETHEREUM_JSONRPC_HTTP_TIMEOUT=60000

# Archive balances (for historical balance queries)
ETHEREUM_JSONRPC_DISABLE_ARCHIVE_BALANCES=false
```

### 2. Frontend Configuration (`docker-compose/envs/common-frontend.env`)

#### **Network Display Settings** (REQUIRED)

```bash
# Network name displayed in UI
NEXT_PUBLIC_NETWORK_NAME=Your Chain Name

# Short network name
NEXT_PUBLIC_NETWORK_SHORT_NAME=YOUR_CHAIN

# Network ID (must match CHAIN_ID from backend)
NEXT_PUBLIC_NETWORK_ID=1337

# Native currency name
NEXT_PUBLIC_NETWORK_CURRENCY_NAME=Your Coin Name

# Native currency symbol
NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL=YOUR_SYMBOL

# Currency decimals (usually 18 for EVM chains)
NEXT_PUBLIC_NETWORK_CURRENCY_DECIMALS=18
```

#### **API Configuration**

```bash
# Backend API host
NEXT_PUBLIC_API_HOST=localhost

# Backend API protocol
NEXT_PUBLIC_API_PROTOCOL=http

# API base path
NEXT_PUBLIC_API_BASE_PATH=/

# WebSocket protocol
NEXT_PUBLIC_API_WEBSOCKET_PROTOCOL=ws
```

#### **Application Settings**

```bash
# Frontend host
NEXT_PUBLIC_APP_HOST=localhost

# Frontend protocol
NEXT_PUBLIC_APP_PROTOCOL=http

# Is testnet?
NEXT_PUBLIC_IS_TESTNET=false

# Homepage charts to display
NEXT_PUBLIC_HOMEPAGE_CHARTS=['daily_txs']
```

#### **Microservices URLs**

```bash
# Stats service
NEXT_PUBLIC_STATS_API_HOST=http://localhost:8080

# Visualizer service
NEXT_PUBLIC_VISUALIZE_API_HOST=http://localhost:8081
```

## Configuration Examples

### Example 1: Local Development Chain

**Backend (`common-blockscout.env`):**
```bash
ETHEREUM_JSONRPC_VARIANT=geth
ETHEREUM_JSONRPC_HTTP_URL=http://host.docker.internal:8545/
ETHEREUM_JSONRPC_TRACE_URL=http://host.docker.internal:8545/
CHAIN_ID=1337
COIN_NAME=Ether
COIN=ETH
```

**Frontend (`common-frontend.env`):**
```bash
NEXT_PUBLIC_NETWORK_NAME=Local Development Chain
NEXT_PUBLIC_NETWORK_SHORT_NAME=Local
NEXT_PUBLIC_NETWORK_ID=1337
NEXT_PUBLIC_NETWORK_CURRENCY_NAME=Ether
NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL=ETH
NEXT_PUBLIC_NETWORK_CURRENCY_DECIMALS=18
```

### Example 2: Remote Production Chain

**Backend (`common-blockscout.env`):**
```bash
ETHEREUM_JSONRPC_VARIANT=geth
ETHEREUM_JSONRPC_HTTP_URL=https://rpc.yourchain.com/
ETHEREUM_JSONRPC_TRACE_URL=https://rpc.yourchain.com/
ETHEREUM_JSONRPC_WS_URL=wss://rpc.yourchain.com/
CHAIN_ID=12345
COIN_NAME=YourCoin
COIN=YCN
BLOCKSCOUT_HOST=explorer.yourchain.com
BLOCKSCOUT_PROTOCOL=https
```

**Frontend (`common-frontend.env`):**
```bash
NEXT_PUBLIC_NETWORK_NAME=Your Chain Mainnet
NEXT_PUBLIC_NETWORK_SHORT_NAME=YCN
NEXT_PUBLIC_NETWORK_ID=12345
NEXT_PUBLIC_NETWORK_CURRENCY_NAME=YourCoin
NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL=YCN
NEXT_PUBLIC_NETWORK_CURRENCY_DECIMALS=18
NEXT_PUBLIC_API_HOST=explorer.yourchain.com
NEXT_PUBLIC_API_PROTOCOL=https
NEXT_PUBLIC_APP_HOST=explorer.yourchain.com
NEXT_PUBLIC_APP_PROTOCOL=https
NEXT_PUBLIC_IS_TESTNET=false
```

## Special Chain Types

### For XRPL EVM Testnet (Currently Active)

The configuration files are currently set up for XRPL EVM Testnet:

**Backend (`common-blockscout.env`):**
```bash
ETHEREUM_JSONRPC_HTTP_URL=https://rpc.testnet.xrplevm.org
ETHEREUM_JSONRPC_TRACE_URL=https://rpc.testnet.xrplevm.org
ETHEREUM_JSONRPC_WS_URL=wss://full-history-bb325630.testnet.xrplevm.org
ETHEREUM_JSONRPC_FALLBACK_HTTP_URL=https://full-history-bb325630.testnet.xrplevm.org
ETHEREUM_JSONRPC_FALLBACK_TRACE_URL=https://full-history-bb325630.testnet.xrplevm.org
ETHEREUM_JSONRPC_FALLBACK_WS_URL=wss://full-history-bb325630.testnet.xrplevm.org
CHAIN_ID=1449000
COIN_NAME=XRP
COIN=XRP
FIRST_BLOCK=2162539
TRACE_FIRST_BLOCK=4900000
ETHEREUM_JSONRPC_DISABLE_ARCHIVE_BALANCES=true
INDEXER_DISABLE_BEACON_BLOB_FETCHER=true
INDEXER_INTERNAL_TRANSACTIONS_FETCH_ORDER=desc
# Conservative concurrency for testnet
INDEXER_INTERNAL_TRANSACTIONS_BATCH_SIZE=1
INDEXER_INTERNAL_TRANSACTIONS_CONCURRENCY=1
INDEXER_RECEIPTS_BATCH_SIZE=1
INDEXER_RECEIPTS_CONCURRENCY=1
INDEXER_COIN_BALANCES_BATCH_SIZE=1
INDEXER_COIN_BALANCES_CONCURRENCY=1
INDEXER_TOKEN_BALANCES_BATCH_SIZE=1
INDEXER_TOKEN_BALANCES_CONCURRENCY=1
```

**Frontend (`common-frontend.env`):**
```bash
NEXT_PUBLIC_NETWORK_NAME=XRPL EVM
NEXT_PUBLIC_NETWORK_SHORT_NAME=XRPL EVM
NEXT_PUBLIC_NETWORK_ID=1449000
NEXT_PUBLIC_NETWORK_CURRENCY_NAME=XRP
NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL=XRP
NEXT_PUBLIC_NETWORK_CURRENCY_DECIMALS=18
NEXT_PUBLIC_IS_TESTNET=true
```

### For XRPL EVM Mainnet

To switch to mainnet, update these values:

**Backend (`common-blockscout.env`):**
```bash
ETHEREUM_JSONRPC_HTTP_URL=https://rpc.xrplevm.org
ETHEREUM_JSONRPC_TRACE_URL=https://rpc.xrplevm.org
ETHEREUM_JSONRPC_WS_URL=wss://ws.xrplevm.org
ETHEREUM_JSONRPC_FALLBACK_HTTP_URL=https://xrplevm.buildintheshade.com
ETHEREUM_JSONRPC_FALLBACK_WS_URL=wss://xrplevm.buildintheshade.com
CHAIN_ID=1440000
COIN_NAME=XRP
COIN=XRP
# Remove or comment out FIRST_BLOCK / TRACE_FIRST_BLOCK for mainnet
```

**Frontend (`common-frontend.env`):**
```bash
NEXT_PUBLIC_NETWORK_NAME=XRPL EVM Mainnet
NEXT_PUBLIC_NETWORK_SHORT_NAME=XRPL EVM
NEXT_PUBLIC_NETWORK_ID=1440000
NEXT_PUBLIC_NETWORK_CURRENCY_NAME=XRP
NEXT_PUBLIC_NETWORK_CURRENCY_SYMBOL=XRP
NEXT_PUBLIC_NETWORK_CURRENCY_DECIMALS=18
NEXT_PUBLIC_IS_TESTNET=false
```

### For Other XRP Sidechains

If you're configuring for a different XRP sidechain, you may need:

```bash
# Chain type (if Blockscout has specific XRP support)
CHAIN_TYPE=

# Custom supply module if needed
# SUPPLY_MODULE=

# Chain-specific contracts
# METADATA_CONTRACT=
# VALIDATORS_CONTRACT=
```

## Native XRP Sentinel Token (Manual Database Step Required)

This fork's main customization surfaces **native XRP as a pseudo-ERC-20 token** at the sentinel address:

```
0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
```

### How it works

- The coin balance fetcher (`apps/indexer/lib/indexer/fetcher/coin_balance/helper.ex`) writes fetched native coin balances not only to the usual coin balance tables, but **also** to `address_token_balances` and `address_current_token_balances`, using the sentinel address as `token_contract_address_hash` with `token_type` `ERC-20`. This makes native XRP appear in address token balance lists alongside real ERC-20 tokens. Note this applies to `import_fetched_balances/2`; the daily-balance path (`import_fetched_daily_balances/2`) is not customized and writes no sentinel rows, so the sentinel balance can transiently lag the address's coin balance.
- The token balance fetcher (`apps/indexer/lib/indexer/fetcher/token_balance/helper.ex`) special-cases the sentinel address in the opposite direction: balances recorded against it also update the address's `fetched_coin_balance`.
- The separate React frontend special-cases this exact address to render the XRP logo for it.

### The manual step

For the sentinel to actually render as a token in the UI/API, **a row must exist in the `tokens` table for that address**. Nothing in this repository seeds it — there is no migration, seed script, or indexer code that inserts it. It must be created manually (out-of-band) in the database after initial setup, otherwise the balance rows reference a token that does not exist and native XRP will not display as a token.

Per the schema in `apps/explorer/lib/explorer/chain/token.ex`, the `tokens` table is keyed by `contract_address_hash`, requires a `type` (use `ERC-20` to match what the indexer writes), and has optional `name`, `symbol`, and `decimals` columns (for XRP: name `XRP`, symbol `XRP`, decimals `18`). Before inserting, confirm the exact column list and NOT NULL constraints (e.g. timestamp columns) against that schema file and the migrations in `apps/explorer/priv/repo/migrations/` — do not assume defaults.

### For PoA (Proof of Authority) Chains

```bash
CHAIN_TYPE=poa
# Hide block miner if not applicable
# HIDE_BLOCK_MINER=true
```

### For L2s (Optimism, Arbitrum, etc.)

Blockscout has built-in support for various L2s. Check the docker-compose files:
- `docker-compose/erigon.yml` - For Erigon-based chains
- `docker-compose/geth.yml` - For Geth-based chains
- `docker-compose/hardhat-network.yml` - For Hardhat networks

## Additional Customization Options

### Market Data (Optional)

```bash
# Enable market data
DISABLE_MARKET=false

# Market data sources
MARKET_COINGECKO_COIN_ID=your-coin-id
MARKET_COINGECKO_API_KEY=your-api-key
```

### API Rate Limiting

```bash
# Disable rate limiting (not recommended for production)
# API_RATE_LIMIT_DISABLED=true

# Rate limits
API_RATE_LIMIT=50
API_RATE_LIMIT_BY_IP=300
```

### Indexer Performance

```bash
# Batch sizes for indexing
INDEXER_CATCHUP_BLOCKS_BATCH_SIZE=10
INDEXER_INTERNAL_TRANSACTIONS_BATCH_SIZE=10

# Concurrency settings
INDEXER_CATCHUP_BLOCKS_CONCURRENCY=4
```

### Security Settings

```bash
# ReCAPTCHA (for production)
RE_CAPTCHA_DISABLED=false
# RE_CAPTCHA_SECRET_KEY=your-secret-key
# RE_CAPTCHA_V3_SECRET_KEY=your-v3-secret-key

# Admin panel
ADMIN_PANEL_ENABLED=false
```

## Step-by-Step Setup

1. **Edit Backend Config:**
   ```bash
   nano docker-compose/envs/common-blockscout.env
   ```
   - Set `ETHEREUM_JSONRPC_HTTP_URL` to your RPC endpoint
   - Set `CHAIN_ID` to your chain ID
   - Set `COIN_NAME` and `COIN` to your native currency
   - Generate a new `SECRET_KEY_BASE` (use `mix phx.gen.secret` or online generator)

2. **Edit Frontend Config:**
   ```bash
   nano docker-compose/envs/common-frontend.env
   ```
   - Set `NEXT_PUBLIC_NETWORK_NAME` and related fields
   - Set `NEXT_PUBLIC_NETWORK_ID` to match your `CHAIN_ID`
   - Configure currency settings

3. **Start Services:**
   ```bash
   cd docker-compose
   docker-compose up --build
   ```

4. **Verify Connection:**
   - Check backend logs: `docker-compose logs backend`
   - Access explorer at: `http://localhost`
   - Check API at: `http://localhost/api`

## Troubleshooting

### Connection Issues

- **Linux users**: Use `http://0.0.0.0:8545/` instead of `http://localhost:8545/` for local nodes
- **Docker networking**: Use `host.docker.internal` to access host machine from containers
- **Remote nodes**: Ensure your RPC endpoint is accessible and CORS is configured

### Database Issues

- Ensure PostgreSQL is running: `docker-compose ps db`
- Check database logs: `docker-compose logs db`
- Reset database if needed: `docker-compose down -v` (WARNING: deletes all data)

### Indexing Issues

- Check indexer logs: `docker-compose logs backend | grep indexer`
- Verify RPC endpoint is responding: `curl -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' YOUR_RPC_URL`

## Full Documentation

For complete documentation on all environment variables, see:
- [Blockscout Environment Variables](https://docs.blockscout.com/setup/env-variables)
- [Frontend Environment Variables](https://github.com/blockscout/frontend/blob/main/docs/ENVS.md)

## Notes

- Always generate a new `SECRET_KEY_BASE` for production deployments
- Keep your RPC endpoint secure and rate-limited
- Consider using fallback RPC URLs for production
- Test configuration changes in a development environment first
- Monitor database size as indexing progresses

