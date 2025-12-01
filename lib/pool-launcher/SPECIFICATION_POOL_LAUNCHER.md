# Pool Launcher Specification

## Overview
The Pool Launcher allows users to create ("launch") new pools consisting of user supplied tokens as well as whitelisted pairable tokens.
The contract handles the creation of the pool, the supplying and optional locking of seed liquidity. Each pool type will have its own pool launcher contract.

By standardizing the rules when launching and additionally locking liquidity, the pool launcher aims to foster a more secure and curated landscape of pools.

Furthermore, the Pool Launcher allows for calculating APRs for pools created through it, that don’t have a gauge yet. This is done by storing the pool creation timestamp when the pool is launched.

Additionally, the team can flag certain Pools as “Emerging” which will be a visible tag on pools in our App.

### Pool Launcher
#### Launch
- Creates a new pool of a given pool type for a given token and pairable token.
  - Pairable tokens are high liquidity tokens that are whitelisted (e.g. WETH / USDC).
- Deposits user supplied tokens into the pool as liquidity.
    - Any leftover tokens are refunded to the user.
- If the liquidity is locked, a locker contract will be created and the liquidity will be locked for the specified duration.
- If the liquidity is not locked, it will be returned to the user.
- Users can supply the tick spacing for slipstream pools, but it must be supported on the slipstream factory.
- Users can specify the lock duration for liquidity locks.
- Users can set the minimum amount of tokens to be deposited as liquidity in order to manage slippage if the pool already exists.

#### Migrate
- Migrates the given pool to a new pool launcher contract.
- It uses an existing locker as liquidity on the new pool launcher to allow locked liquidity to be migrated.
  - Migrates liquidity by calling the `migrate` function on the locker factory to unlock funds for the migration, and then calling `launch()` on the new pool launcher using unlocked funds.
- Migration is restricted to the owner of the Locker to be migrated and is only allowed once the new pool launcher contract is set.
- If there’s no intention of using an existing locker for the migration, the launch function can be called directly in the new pool launcher.
- Useful for seamlessly migrating existing pools into a new pool launcher contract, facilitating the redeployment of pool launcher contracts and pool factories.
- Users can specify the following parameters to manage migration slippage if the pool already exists in the new factory:
    - The minimum amount of tokens to be unlocked from the old LP.
    - The minimum amount of tokens to be migrated to the new LP.
- Leftover tokens from migration slippage or the old Locker balance stay locked in the new `Locker` and can be used to increase the locked position (i.e.: via `Locker.increaseLiquidity()`).
  - Migration leftovers are automatically transferred to the user once the LP is unlocked.

#### SetNewPoolLauncher
- Sets the new pool launcher contract that will be used for migrations.
- Only callable by the pool launcher owner.

#### FlagEmerging
- Flags a pool as emerging. Used in the UI to display whether a gauge can be created for the pool soon.
- Only callable by the pool launcher owner.

#### UnflagEmerging
- Removes the emerging flag for a pool.
- Only callable by the pool launcher owner.

#### AddPairableToken
- Adds a token to the list of whitelisted tokens.
- On the launch function, new pool launcher tokens can only be paired against whitelisted tokens on this list.

#### RemovePairableToken
- Removes a token from the list of tokens available to pair pool launcher tokens with.

### Pools
- Returns the pool launcher struct for the given underlying pool (pool creation timestamp, underlying pool, pool launcher token, token that is paired with).
