// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/StdJson.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ICreateX} from "createX/ICreateX.sol";

import {CreateXLibrary} from "src/libraries/CreateXLibrary.sol";

import {Constants} from "script/constants/Constants.sol";

abstract contract DeployFixture is Script, Constants {
    using CreateXLibrary for bytes11;

    error InvalidOutputFilename();
    error InvalidAddress(address expected, address output);

    uint256 public constant ROOT_CHAIN_ID = 10;

    ICreateX public cx = CreateXLibrary.CREATEX;

    /// @dev Used by tests to disable the logging
    bool internal isTest;

    address public deployer = 0x358f2C837cA4Df1a0372Bb87Bd4eE485f38BE05E;

    function setUp() public virtual;

    function run() external {
        vm.startBroadcast(deployer);
        verifyCreate3();

        deploy();
        logParams();
        logOutput();

        vm.stopBroadcast();
    }

    function deploy() internal virtual;

    function logParams() internal view virtual;

    function logOutput() internal virtual;

    /// @dev Check if the computed address matches the address produced by the deployment
    function checkAddress(bytes11 _entropy, address _output) internal view {
        address computedAddress = _entropy.computeCreate3Address({_deployer: deployer});
        if (computedAddress != _output) {
            revert InvalidAddress(computedAddress, _output);
        }
    }

    function verifyCreate3() internal view {
        /// if not run locally
        if (block.chainid != 31337) {
            uint256 size;
            address contractAddress = address(cx);
            assembly {
                size := extcodesize(contractAddress)
            }

            bytes memory bytecode = new bytes(size);
            assembly {
                extcodecopy(contractAddress, add(bytecode, 32), 0, size)
            }

            assert(keccak256(bytecode) == bytes32(0xbd8a7ea8cfca7b4e5f5041d7d4b17bc317c5ce42cfbc42066a00cf26b43eb53f));
        }
    }
}
