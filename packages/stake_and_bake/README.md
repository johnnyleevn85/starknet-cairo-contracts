# Stake and Bake

## Overview

Convenience contract for users who wish to stake their `BTC` and deposit `LBTC` in a vault in the same transaction.

- Stake And Bake implements the generic stake and bake logic - it wraps over the LBTC 'automint' functionality and takes in some extra parameters to permit the minted LBTC to a depositor, and then deposits it. The depositor then returns the staked tokens back to the owner such that they can take it out when they wish.