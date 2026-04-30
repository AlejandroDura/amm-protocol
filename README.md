# Custom AMM protocol

## 📄 Description

This project consists of a custom Automated Market Maker (AMM) using the x*y=k formula to handle the
pool price and liquidity.

## 🎯 Objectives

The main idea is to create several pools to support various cryptocurrency pairs.

At the moment we have the pool code, which defines a pool and all its functionality to add, remove/retrieve and swap tokens. The pool.sol test phase is nearly done. We may need to add some integration tests with tokens.

We need to create now a contract that creates and stores several pools.

Note: The project is not finished. We are improving it and adding new features.


## 🗂️ Project structure

The main pool code can be found in:

- src/Pool.sol. This file defines a pool with its algorithm.

Tests:

- test/fuzz for pool.sol fuzz testing
- test/unit for pool.sol unit testing

## 🛠️ Thech Stack

- Solidity
- Foundry



