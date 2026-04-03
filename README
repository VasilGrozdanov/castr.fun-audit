# castr.fun

A next-generation token launchpad on Base. Bonding curve mechanics, NFT-based locking, TWAP rewards, and seamless Aerodrome Slipstream migration - built for fair launches and long-term liquidity.

---

## Overview

castr.fun is a permissionless token launchpad on Base that replaces the standard pump-and-dump lifecycle with mechanics designed for sustainable growth:

- **Bonding Curve Launch** — continuous pricing targeting an ~800M token cap with a ~4.5 ETH graduation goal
- **NFT-Based Locking** — transferable lock NFTs with a 30% boost cap and burn-to-claim mechanics, replacing veToken governance
- **TWAP Rewards** — 24-hour cycles rewarding the top token by TWAP
- **Dynamic Sell Lock** — 5 min–24 hr sell cooldown based on buyer timing, protecting against early dumps
- **Aerodrome Slipstream Migration** — automatic LP creation and permanent LP lock on graduation
- **Fee Distribution** — 1% buy/sell fee, split 50% protocol / 50% buyback-and-burn

---

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [GNU Make](https://www.gnu.org/software/make/)
- [Git](https://git-scm.com/)

---

## Installation

### Option A — Make

```bash
make install
```

### Option B — Manual

```bash
forge install smartcontractkit/chainlink-brownie-contracts --no-git && \
forge install foundry-rs/forge-std --no-git && \
forge install openzeppelin/openzeppelin-contracts@v5.4.0 --no-git && \
forge install openzeppelin/openzeppelin-contracts-upgradeable@v5.4.0 --no-git && \
forge install PaulRBerg/prb-math@v4.1.0 --no-git && \
forge install aerodrome-finance/slipstream@v1.0.0 --no-git && \
forge install velodrome-finance/pool-launcher --no-git && \
forge install beefyfinance/beefy-contracts --no-git
```

---

## Build

```bash
forge build
```

---

## Test

```bash
# Run all tests
forge test --rpc-url $BASE_RPC_URL

# Run with verbosity (recommended for debugging)
forge test --rpc-url $BASE_RPC_URL -vvv

# Run a specific test file
forge test --match-path test/unit/BondingCurveTest.t.sol --rpc-url $BASE_RPC_URL -vvv
```

---

## Environment

Copy `.env.example` to `.env` and fill in:

```env
BASE_RPC_URL="<your_bases_mainnet_rpc_url>"
BASESCAN_API_KEY="<your_basescan_api_key>"
```

---

## Project Structure

```
script/
└── DeployProject.s.sol
src/
├── interfaces/
│   ├── external/                  # Minimal interfaces for Slipstream / Aerodrome
│   │   ├── ICLFactory.sol
│   │   ├── ILocker.sol
│   │   └── INonfungiblePositionManager.sol
│   ├── IBondingCurve.sol
│   ├── IBondingCurveFactory.sol
│   ├── IFeeAccount.sol
│   ├── ILiquidityLocker.sol
│   ├── ILiquidityMigrator.sol
│   ├── ILockManager.sol
│   ├── ILockPositionsNFT.sol
│   └── IRewardResolver.sol
└── libraries/
    ├── utils/
    │   ├── NFTDescriptor.sol      # On-chain NFT metadata
    │   ├── NFTSVG.sol             # SVG renderer
    │   ├── StringValidator.sol
    │   └── VestingCalculator.sol
    ├── BancorBondingCurve.sol     # Bancor formula
    ├── BondingCurve.sol           # Core bonding curve logic
    ├── BondingCurveFactory.sol    # EIP-1167 clone factory
    ├── BondingCurvesStorage.sol
    ├── BurnableToken.sol          # Clone base token
    ├── FeeAccount.sol             # Fee distribution
    ├── LiquidityLocker.sol
    ├── LiquidityMigrator.sol      # Aerodrome Slipstream migration + LP lock
    ├── LockManager.sol            # NFT-based lock system
    ├── LockPositionsNFT.sol       # Transferable lock NFTs
    └── RewardResolver.sol         # TWAP reward cycles
test/
├── fuzz/
│   ├── Handler.t.sol
│   └── Invariants.t.sol
├── integration/
└── mocks/
└── unit/
```

---

## Dependencies

| Package                                         | Version |
| ----------------------------------------------- | ------- |
| openzeppelin/openzeppelin-contracts             | v5.4.0  |
| openzeppelin/openzeppelin-contracts-upgradeable | v5.4.0  |
| PaulRBerg/prb-math                              | v4.1.0  |
| aerodrome-finance/slipstream                    | v1.0.0  |
| velodrome-finance/pool-launcher                 | latest  |
| smartcontractkit/chainlink-brownie-contracts    | latest  |
| beefyfinance/beefy-contracts                    | latest  |
| foundry-rs/forge-std                            | latest  |

---


## Deployment
 
```bash
# Dry run
forge script script/DeployProject.s.sol --rpc-url $BASE_RPC_URL --account production
 
# Broadcast
forge script script/DeployProject.s.sol --rpc-url $BASE_RPC_URL --account production --broadcast --verify
```
 
---
 
## License
 
UNLICENSED — All rights reserved.