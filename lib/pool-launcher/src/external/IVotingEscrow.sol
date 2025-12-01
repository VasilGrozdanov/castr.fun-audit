// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVotingEscrow {
    /// @notice Address of token (VELO) used to create a veNFT
    function token() external view returns (address);
}
