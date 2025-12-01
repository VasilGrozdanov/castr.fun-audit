// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/// @dev Helper contract to avoid reverts in refund tests after updating the block number.
///      Can consider removing later if no longer needed.
contract TestOwner is ERC721Holder {
    receive() external payable {}
}
