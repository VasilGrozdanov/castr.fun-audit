// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "./DeployFixture.sol";

import {V2PoolLauncher} from "../src/extensions/v2/V2PoolLauncher.sol";
import {V2LockerFactory} from "../src/extensions/v2/V2LockerFactory.sol";
import {V2Locker} from "../src/extensions/v2/V2Locker.sol";

abstract contract DeployV2Fixture is DeployFixture {
    using CreateXLibrary for bytes11;

    struct DeploymentParameters {
        address v2Factory;
        address v2Router;
        address voter;
        address owner;
        string outputFilename;
    }

    DeploymentParameters internal _params;

    V2PoolLauncher public v2PoolLauncher;
    V2LockerFactory public v2LockerFactory;
    V2Locker public v2LockerImplementation;

    function deploy() internal override {
        address _deployer = deployer;

        v2PoolLauncher = V2PoolLauncher(V2_POOL_LAUNCHER_ENTROPY.computeCreate3Address({_deployer: _deployer}));
        v2LockerImplementation = V2Locker(V2_LOCKER_ENTROPY.computeCreate3Address({_deployer: _deployer}));
        v2LockerFactory = V2LockerFactory(
            cx.deployCreate3({
                salt: V2_LOCKER_FACTORY_ENTROPY.calculateSalt({_deployer: _deployer}),
                initCode: abi.encodePacked(
                    type(V2LockerFactory).creationCode,
                    abi.encode(
                        _params.owner, // locker factory owner
                        v2PoolLauncher, // pool launcher
                        v2LockerImplementation, // locker implementation
                        _params.v2Factory, // v2 pool factory
                        _params.v2Router, // v2 router
                        _params.voter // voter
                    )
                )
            })
        );
        checkAddress({_entropy: V2_LOCKER_FACTORY_ENTROPY, _output: address(v2LockerFactory)});

        v2LockerImplementation = V2Locker(
            cx.deployCreate3({
                salt: V2_LOCKER_ENTROPY.calculateSalt({_deployer: _deployer}),
                initCode: abi.encodePacked(
                    type(V2Locker).creationCode,
                    abi.encode(
                        v2LockerFactory, // locker factory
                        block.chainid == ROOT_CHAIN_ID // root
                    )
                )
            })
        );
        checkAddress({_entropy: V2_LOCKER_ENTROPY, _output: address(v2LockerImplementation)});

        v2PoolLauncher = V2PoolLauncher(
            cx.deployCreate3({
                salt: V2_POOL_LAUNCHER_ENTROPY.calculateSalt({_deployer: _deployer}),
                initCode: abi.encodePacked(
                    type(V2PoolLauncher).creationCode,
                    abi.encode(
                        _params.owner, // pool launcher owner
                        _params.v2Factory, // v2 pool factory
                        _params.v2Router, // v2 router
                        v2LockerFactory // v2 locker factory
                    )
                )
            })
        );
        checkAddress({_entropy: V2_POOL_LAUNCHER_ENTROPY, _output: address(v2PoolLauncher)});
    }

    function logParams() internal view override {
        console.log("V2LockerImplementation: ", address(v2LockerImplementation));
        console.log("V2LockerFactory: ", address(v2LockerFactory));
        console.log("V2PoolLauncher: ", address(v2PoolLauncher));
    }

    function logOutput() internal override {
        if (isTest) return;
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/deployment-addresses/", _params.outputFilename));
        if (keccak256(bytes(_params.outputFilename)) == keccak256(bytes(""))) revert InvalidOutputFilename();
        vm.writeJson(vm.serializeAddress("", "V2LockerImplementation", address(v2LockerImplementation)), path);
        vm.writeJson(vm.serializeAddress("", "V2LockerFactory", address(v2LockerFactory)), path);
        vm.writeJson(vm.serializeAddress("", "V2PoolLauncher", address(v2PoolLauncher)), path);
    }
}
