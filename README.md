# Hacken Webinar: Uniswap V4 – Flash & Custom Accounting

This repository contains the codebase for the **Uniswap V4: Flash and Custom Accounting** webinar, which demonstrates advanced integration techniques with Uniswap V4 hooks and flash accounting.

---

## 🎯 Purpose

This project explores:

- Custom swap fee accounting using `beforeSwap` hooks
- Flash accounting logic with deltas
- Interaction with `PoolManager` through an integration contract

## Getting Started

### 1. Install dependencies

npm install

### 2. Compile contracts with Foundry

forge build

### 3. Run tests

forge test --match-test testAddLiquidityAndSwap -vvvv
