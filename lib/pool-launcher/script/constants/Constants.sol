// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

/// @notice Constants used by Create3 deployment scripts
abstract contract Constants {
    // 0 - 10 is reserved for use by v2 contracts

    bytes11 public constant V2_POOL_LAUNCHER_ENTROPY = 0x0000000000000000000001;
    bytes11 public constant V2_LOCKER_ENTROPY = 0x0000000000000000000002;
    bytes11 public constant V2_LOCKER_FACTORY_ENTROPY = 0x0000000000000000000003;

    // 10 - 20 is reserved for use by slipstream contracts

    bytes11 public constant CL_POOL_LAUNCHER_ENTROPY = 0x0000000000000000000010;
    bytes11 public constant CL_LOCKER_ENTROPY = 0x0000000000000000000011;
    bytes11 public constant CL_LOCKER_FACTORY_ENTROPY = 0x0000000000000000000012;
}
