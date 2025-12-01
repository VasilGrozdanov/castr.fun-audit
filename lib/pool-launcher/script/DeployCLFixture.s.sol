// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "./DeployFixture.sol";

import {CLPoolLauncher} from "../src/extensions/cl/CLPoolLauncher.sol";
import {CLLockerFactory} from "../src/extensions/cl/CLLockerFactory.sol";
import {CLLocker} from "../src/extensions/cl/CLLocker.sol";

abstract contract DeployCLFixture is DeployFixture {
    using CreateXLibrary for bytes11;

    struct DeploymentParameters {
        address owner;
        address voter;
        address nfpManager;
        string outputFilename;
    }

    /// @dev Pool launcher contracts for CL pools
    CLLocker public clLockerImplementation;
    CLLockerFactory public clLockerFactory;
    CLPoolLauncher public clPoolLauncher;

    DeploymentParameters internal _params;

    function deploy() internal override {
        address _deployer = deployer;

        clPoolLauncher = CLPoolLauncher(CL_POOL_LAUNCHER_ENTROPY.computeCreate3Address({_deployer: _deployer}));
        clLockerImplementation = CLLocker(CL_LOCKER_ENTROPY.computeCreate3Address({_deployer: _deployer}));
        clLockerFactory = CLLockerFactory(
            cx.deployCreate3({
                salt: CL_LOCKER_FACTORY_ENTROPY.calculateSalt({_deployer: _deployer}),
                initCode: abi.encodePacked(
                    type(CLLockerFactory).creationCode,
                    abi.encode(
                        _params.owner, // locker factory owner
                        clPoolLauncher, // pool launcher
                        clLockerImplementation, // locker implementation
                        _params.nfpManager, // nfpManager
                        _params.voter // voter
                    )
                )
            })
        );
        checkAddress({_entropy: CL_LOCKER_FACTORY_ENTROPY, _output: address(clLockerFactory)});

        clLockerImplementation = CLLocker(
            cx.deployCreate3({
                salt: CL_LOCKER_ENTROPY.calculateSalt({_deployer: _deployer}),
                initCode: abi.encodePacked(
                    type(CLLocker).creationCode,
                    abi.encode(
                        clLockerFactory, // locker factory
                        block.chainid == ROOT_CHAIN_ID // root
                    )
                )
            })
        );
        checkAddress({_entropy: CL_LOCKER_ENTROPY, _output: address(clLockerImplementation)});

        clPoolLauncher = CLPoolLauncher(
            cx.deployCreate3({
                salt: CL_POOL_LAUNCHER_ENTROPY.calculateSalt({_deployer: _deployer}),
                initCode: abi.encodePacked(
                    type(CLPoolLauncher).creationCode,
                    abi.encode(
                        _params.owner, // pool launcher owner
                        _params.nfpManager, // nfpManager
                        clLockerFactory // cl locker factory
                    )
                )
            })
        );
        checkAddress({_entropy: CL_POOL_LAUNCHER_ENTROPY, _output: address(clPoolLauncher)});
    }

    function logParams() internal view override {
        if (isTest) return;
        console.log("CLLockerImplementation: ", address(clLockerImplementation));
        console.log("CLLockerFactory: ", address(clLockerFactory));
        console.log("CLPoolLauncher: ", address(clPoolLauncher));
    }

    function logOutput() internal override {
        if (isTest) return;
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/deployment-addresses/", _params.outputFilename));
        if (keccak256(bytes(_params.outputFilename)) == keccak256(bytes(""))) revert InvalidOutputFilename();
        /// @dev This might overwrite an existing output file
        vm.writeJson(vm.serializeAddress("", "CLLockerImplementation", address(clLockerImplementation)), path);
        vm.writeJson(vm.serializeAddress("", "CLLockerFactory", address(clLockerFactory)), path);
        vm.writeJson(vm.serializeAddress("", "CLPoolLauncher", address(clPoolLauncher)), path);
    }
}
