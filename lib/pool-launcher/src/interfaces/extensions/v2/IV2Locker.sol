// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILocker} from "../../ILocker.sol";

interface IV2Locker is ILocker {
    /**
     * @notice The address of the router used to manage liquidity
     * @return Address of the router
     */
    function router() external view returns (address);
}
