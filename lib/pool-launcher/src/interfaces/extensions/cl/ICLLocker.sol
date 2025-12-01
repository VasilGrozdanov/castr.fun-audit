// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INonfungiblePositionManager as INfpm} from "../../../external/INonfungiblePositionManager.sol";
import {ILocker} from "../../ILocker.sol";

interface ICLLocker is ILocker {
    /**
     * @notice The address of the NonfungiblePositionManager that manages CL liquidity positions
     * @return Address of the NonfungiblePositionManager
     */
    function nfpManager() external view returns (INfpm);
}
