// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IFunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/interfaces/IFunctionsClient.sol";

/**
 * @dev Interface for a reward resolver that interacts with Chainlink Functions.
 * This interface defines the events and errors related to reward resolution.
 */
interface IRewardResolver is IFunctionsClient {
    event RequestSent(bytes32 indexed id);
    event RequestFulfilled(bytes32 indexed id);

    error IRewardResolver_OnlyRouterCanFulfill();
}
