// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FeeAccount} from "src/FeeAccount.sol";
import {AddressChecker} from "src/AddressChecker.sol";
import {RewardResolver} from "src/RewardResolver.sol";
import {LiquidityMigrator} from "src/LiquidityMigrator.sol";
import {BondingCurveFactory} from "src/BondingCurveFactory.sol";
import {FactoryManager} from "src/FactoryManager.sol";
import {BondingCurvesStorage} from "src/BondingCurvesStorage.sol";
import {BurnableToken} from "src/BurnableToken.sol";
import {BondingCurve} from "src/BondingCurve.sol";
import {LockPositionsNFT} from "src/LockPositionsNFT.sol";
import {LockManager} from "src/LockManager.sol";
import {LiquidityLocker} from "src/LiquidityLocker.sol";

contract DeployProject is Script {
    // BASE_MAINNET
    address private constant WETH_BASE_MAINNET =
        0x4200000000000000000000000000000000000006;
    address private constant POSITION_MANAGER_BASE_MAINNET =
        0x827922686190790b37229fd06084350E74485b72;
    address private constant FACTORY_BASE_MAINNET =
        0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    address private constant SWAP_ROUTER_BASE_MAINNET =
        0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;

    address public keeperRegistry =
        address(0xf4bAb6A129164aBa9B113cB96BA4266dF49f8743); //  hardcoded for Base mainnet
    uint256 public minWaitPeriod = 24 hours;
    address public beneficiary =
        address(0x3b195607a32C41bD613d48BAb5a9a7761022D4C3);
    address[] public dexes;

    uint64 private constant SUBSCRIPTION_ID = 0;

    function run() external returns (address) {
        dexes.push(FACTORY_BASE_MAINNET);
        // Begin broadcasting
        vm.startBroadcast();

        AddressChecker addressChecker = new AddressChecker(dexes);
        console2.log("AddressChecker deployed to:", address(addressChecker));

        RewardResolver rewardResolverImpl = new RewardResolver();
        ERC1967Proxy proxy = new ERC1967Proxy(address(rewardResolverImpl), "");
        RewardResolver rewardResolver = RewardResolver(address(proxy));
        rewardResolver.initialize(SUBSCRIPTION_ID);
        console2.log("RewardResolver deployed to:", address(rewardResolver));

        address treasury = beneficiary;
        console2.log("Treasury deployed to:", address(treasury));

        FeeAccount feeAccountImpl = new FeeAccount();
        proxy = new ERC1967Proxy(address(feeAccountImpl), "");
        FeeAccount feeAccount = FeeAccount(payable(address(proxy)));
        feeAccount.initialize(
            SWAP_ROUTER_BASE_MAINNET,
            address(rewardResolver),
            address(treasury)
        );
        console2.log("FeeAccount deployed to:", address(feeAccount));
        LiquidityLocker liquidityLocker = new LiquidityLocker(address(0));
        console2.log("LiquidityLocker deployed to:", address(liquidityLocker));
        feeAccount.setLiquidityLocker(address(liquidityLocker));

        // BurnableToken burnableTokenImpl = new BurnableToken();
        // LockManager lockManagerImpl = new LockManager();
        // LockPositionsNFT lockPositionsNFTImpl = new LockPositionsNFT();

        LiquidityMigrator migrator = new LiquidityMigrator(
            payable(address(feeAccount)),
            POSITION_MANAGER_BASE_MAINNET,
            FACTORY_BASE_MAINNET,
            WETH_BASE_MAINNET,
            address(liquidityLocker),
            address(0)
        );
        liquidityLocker.setLiquidityMigrator(address(migrator));
        console2.log("LiquidityMigrator deployed to:", address(migrator));
        feeAccount.setLiquidityMigrator(address(migrator));
        BondingCurvesStorage bondingCurvesStorageImpl = new BondingCurvesStorage();
        proxy = new ERC1967Proxy(address(bondingCurvesStorageImpl), "");
        BondingCurvesStorage bondingCurvesStorage = BondingCurvesStorage(
            address(proxy)
        );
        bondingCurvesStorage.initialize(
            address(migrator),
            address(addressChecker),
            address(new BondingCurve()),
            address(new BurnableToken()),
            address(new LockManager()),
            address(new LockPositionsNFT())
        );
        console2.log(
            "BondingCurvesStorage deployed to:",
            address(bondingCurvesStorage)
        );
        BondingCurveFactory bondingCurveFactory = new BondingCurveFactory(
            address(bondingCurvesStorage)
        );
        console2.log(
            "BondingCurveFactory deployed to:",
            address(bondingCurveFactory)
        );
        FactoryManager factoryManagerImpl = new FactoryManager();
        proxy = new ERC1967Proxy(address(factoryManagerImpl), "");
        FactoryManager factoryManager = FactoryManager(address(proxy));
        factoryManager.initialize(address(bondingCurveFactory));
        console2.log("FactoryManager deployed to:", address(factoryManager));

        bondingCurvesStorage.setFactoryManager(address(factoryManager));
        rewardResolver.setFeeAccount(address(feeAccount));
        migrator.setBondingCurveStorage(address(bondingCurvesStorage));
        vm.stopBroadcast();

        return address(migrator);
    }
}
