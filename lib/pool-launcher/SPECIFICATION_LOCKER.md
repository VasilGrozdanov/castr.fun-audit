# Locker Specification

## Overview
Lockers are a fund escrow contract that allows users to lock liquidity in a given pool type
while allowing the owner to manage the position (e.g. claim fees, stake, add incentives). Each pool
type will have its own factory contract that will create child locker contracts for users.

Lockers can be created either by the user via the pool launcher or directly through the factory contract.

Additionally, when creating a Lock, certain parameters can be defined such as:
- beneficiary - Address eligible to receive a percentage of the fees and rewards claimed.
- beneficiary share - The share of fees that the beneficiary is eligible to receive.
- bribeable share - The maximum share of fees and rewards (after deducting the beneficiary’s share) that can be deposited as bribes, via `Locker.bribe()`.

### LockerFactory
The `LockerFactory` is responsible for creating individual `Locker` contracts.

#### Lock
- Allows a user to lock lp tokens or a slipstream nft.
- The locked LP tokens are transferred to a new `Locker` contract created for the user.
- Accepts parameters to specify what liquidity to lock, for how long, and optionally a beneficiary that receives a share of fees/rewards.

#### Unlock
- Makes the necessary checks (including checking the lock duration has ended), updates the necessary mappings/variables in the locker factory and calls the locker (to unlock the LP position to the user).

#### Migrate
- Allows the migration of liquidity to a new locker factory without compromising lock durations and other locker invariants.
- The migrate function in the locker factory can have 1 of 2 scenarios:
    - Called by the pool launcher to complete a migration: it will unlock the lp to be used as liquidity when launching the pool in the new pool launcher contract (see `PoolLauncher.migrate`).
    - Called by the user (and not the pool launcher): it will unlock and remove the lp position from the current locker factory and create the same locked position in the new locker factory.
- Migration is restricted to the owner of the Locker to be migrated and is only allowed once the new locker factory contract is set.
- Users can specify the following parameters to manage slippage in migrations:
    - The minimum amount of tokens to be unlocked from the old LP.
    - The minimum amount of tokens expected to be in the new LP.
- Leftover tokens from migration slippage or the old Locker balance stay locked in the new Locker contract and can be used to increase the Locker's liquidity (i.e.: via `Locker.increaseLiquidity()`).
  - Migration leftovers are automatically transferred to the user once the Locker is unlocked.

#### Locked
- Returns the total locked liquidity for a given pool address.
- The total locked liquidity is the sum of all the liquidity from the lockers in that pool.

#### SetNewLockerFactory
- Sets the new locker factory contract used for migrations.

#### TransferLockerOwnership
- Used by the locker when its ownership is transferred (via `renounceOwnership`/ `transferOwnership` ) to update the locker factory mappings/variables.

#### Lockers
- Returns a list of all the lockers created by this locker factory for the given pool.

#### LockersPerUser
- Returns a list of all the lockers created by this locker factory owned by the given user.

#### LockersPerPoolPerUser
- Returns a list of all the lockers created by this locker factory for the given pool owned by the given user.

### Locker
The `Locker` contract is responsible for holding the locked liquidity and allowing the owner to manage the position.
- Allows the owner to claim fees from a locked position.
- Allows the owner to claim rewards (emissions) from a locked position.
- Allows the owner to stake a locked position.
- Allows the owner to unstake a locked position.
- Allows the owner to unlock a locked position.
- Allows the owner to deposit additional liquidity into the locked position.
  - If the `Locker` holds leftover tokens from a previous migration, they are automatically used to increase the locked position.
- Allows the owner to extend the lock duration of the liquidity position.
- Allows the owner to set the `bribeableShare` percentage.
  - The percentage is used to cap the maximum amount of fees/rewards that can be deposited when bribing via the `Locker`.

#### Unlock
- Unlocks the liquidity and transfers it to the owner.
- Transfers any leftover tokens from a previous migration to the owner.
- Reverts if the unlock date has not been reached.
- Only callable by the locker factory since important checks are done at the factory level.

#### Stake
- Stakes the liquidity in the gauge (in case there is one).
- Reverts if there is no gauge associated with the pool.
- Claims all fees before staking and sends them to the locker owner.

Unstake
- Unstakes the liquidity if staked in the gauge.
- Claims all rewards (emissions) before unstaking and sends them to the locker owner.

#### ClaimFees
- Claims all fees.
- Reverts when the locker is staked.
- Sends a share (beneficiary share) of the claimed fees to the beneficiary and the rest to the specified recipient.

#### ClaimRewards
- Claims all rewards.
- Reverts when the locker is not staked.
- Sends a share (beneficiary share) of the claimed rewards to the beneficiary and the rest to the specified recipient.

#### Bribe
- Directly bribes the underlying pool for the locker with a share (bribeable share) of claimable fees/rewards.
- It claims the fees/rewards and deducts the beneficiary share. From there, the bribeable share is applied and the remaining fee/rewards are sent to the locker owner.

#### IncreaseLiquidity
- Increases the liquidity in the locked position.
- If the `Locker` holds leftover tokens from migration slippage, they are automatically used to increase the locked position.

#### IncreaseDuration
- Increases the locker’s duration.

#### SetBribeableShare
- Sets the new bribeable share for this locker (should be within a certain range).
