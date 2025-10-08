# 💎 LUSD — Decentralized Stablecoin System

A fully on-chain **overcollateralized stablecoin protocol** built with Solidity and Foundry, featuring React + Tailwind front-end for minting, burning, redeeming, and liquidating positions.

> **Live Demo (Frontend)**  
> 🔗 [working on it](https://letiazevedo.com/)  
> 📝 [Smart Contract (Deployed on Ethereum Sepolia Testnet)](https://letiazevedo.com/)

---

## Overview

LUSD is an exogenous decentralized stablecoin backed by **wETH collateral** and designed to maintain stability through **overcollateralization** and **liquidation mechanisms**. Relative Stability Pegged -> $1.00

Users can:

- 💰 Deposit ETH (protocol wrap as WETH) to **mint** LUSD  
- 🔥 **Burn** LUSD to reduce debt  
- 💵 **Redeem** collateral  
- ⚖️ **Liquidate** unhealthy positions  

The UI provides real-time updates on collateral value, minting limits, and health factor metrics.

---

## Smart Contract Architecture

The DSCEngine contract is designed to support multiple collateral assets. For this version, the frontend implements the flow only for wETH to simplify the user experience. The backend is built in Solidity using **Foundry** for deployment, testing, and verification.

###  Core Contracts

- **DSCEngine.sol**:Core logic for minting, burning, redeeming, and liquidation 
- **DecentralizedStableCoin.sol**: ERC20-compliant stablecoin token 
- **PriceFeed integration**: Chainlink AggregatorV3Interface for real-time ETH/USD price updates 

###  Key Mechanisms

- **Overcollateralization** — prevents undercollateralized loans.  
- **Health Factor** — determines user’s liquidation risk.  
  - `> 1.5` → Safe  
  - `1.2–1.5` → At Risk  
  - `1.0–1.2` → Danger Zone  
  - `< 1.0` → Liquidatable  

- **Liquidation Bonus (10%)** — incentivizes third parties to liquidate unsafe positions.  
- **Chainlink Price Feeds** — ensure consistent USD valuations.

---

## Frontend (Next.js + TailwindCSS)

The UI was designed to feel **intuitive and trustworthy**, showcasing DeFi mechanics.  
Each operation is separated into modular “cards” for clarity:

### Core Sections

- **Deposit & Mint** | Wrap ETH → Deposit WETH → Mint LUSD (in one flow)
- **Burn LUSD** | Repay debt to increase your Health Factor 
- **Redeem Collateral** | Withdraw wETH based on remaining collateral 
- **Liquidate** | Cover another user’s debt and claim their collateral (with bonus)

---

## Smart Contract Flow

```text
Deposit ETH  →  DSCEngine wraps  →  Mint LUSD
Burn LUSD    →  Repay debt       →  Increase Health Factor
Redeem ETH   →  Withdraw WETH    →  Decrease Health Factor
Liquidate    →  Burn LUSD        →  Receive collateral (with bonus)
```
---

## Local Installation

### Smart Contracts Setup

```bash
git clone https://github.com/leticiaazevedo/defi-stablecoin
cd smart-contracts
forge install openzeppelin/openzeppelin-contracts chainlink/contracts
forge build
forge coverage
```

![Tests coverage](/frontend-integration/public/tests.png)


### Frontend Setup
```bash
cd frontend-integration
npm install
npm run dev
```

