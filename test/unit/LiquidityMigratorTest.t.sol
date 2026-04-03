// SPDX-License-Identifier: MIT
pragma solidity >=0.8.22 <0.9.0;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {BondingCurvesStorageMock} from "test/mocks/BondingCurvesStorageMock.t.sol";
import {RewardResolverMock} from "test/mocks/RewardResolverMock.t.sol";
import {ISwapRouter} from "@aerodrome-finance/slipstream/periphery/interfaces/ISwapRouter.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ICLPool} from "@aerodrome-finance/slipstream/core/interfaces/ICLPool.sol";
import {TickMath} from "@beefyfinance/beefy-contracts/BIFI/utils/TickMath.sol";
import {INonfungiblePositionManager} from "src/interfaces/external/INonfungiblePositionManager.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LiquidityMigrator, IWETH9} from "src/LiquidityMigrator.sol";
import {BurnableToken} from "src/BurnableToken.sol";
import {FeeAccount} from "src/FeeAccount.sol";
import {BondingCurvesStorage} from "src/BondingCurvesStorage.sol";
import {LockManager, ILockManager} from "src/LockManager.sol";
import {LockPositionsNFT} from "src/LockPositionsNFT.sol";
import {AddressChecker} from "src/AddressChecker.sol";
import {LiquidityLocker} from "src/LiquidityLocker.sol";
import {ICLFactory} from "src/interfaces/external/ICLFactory.sol";

contract LiquidityMigratorTest is Test {
    using Math for uint256;

    IWETH9 private weth;
    BurnableToken private memeCoin;
    // BASE_MAINNET
    address private constant WETH_BASE_MAINNET =
        0x4200000000000000000000000000000000000006;
    address private constant POSITION_MANAGER_BASE_MAINNET =
        0x827922686190790b37229fd06084350E74485b72;
    address private constant FACTORY_BASE_MAINNET =
        0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    address private constant SWAP_ROUTER_BASE_MAINNET =
        0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;

    BondingCurvesStorageMock public bondingCurvesStorage;
    LiquidityMigrator private liquidityMigrator;
    RewardResolverMock private rewardResolverMock;
    address private swapRouter;
    address public keeperRegistry =
        address(0xf4bAb6A129164aBa9B113cB96BA4266dF49f8743); //  hardcoded for Base mainnet
    uint256 public minWaitPeriod = 24 hours;
    uint256 wethAMount = 4.5 ether;
    uint256 LOCK_FLAT_FEE = 0.03 ether;
    uint256 memeCoinAmount = 200e6 ether;
    FeeAccount feeAccount;
    address treasury;
    address USER = makeAddr("castr_test_user_unique");
    address BENEFICIARY = makeAddr("castr_test_beneficiary_unique");
    address OWNER = address(0x3b195607a32C41bD613d48BAb5a9a7761022D4C3);
    address[] dexes;

    receive() external payable {}

    function setUp() public {
        treasury = BENEFICIARY;
        bondingCurvesStorage = new BondingCurvesStorageMock();
        weth = IWETH9(WETH_BASE_MAINNET);

        dexes.push(FACTORY_BASE_MAINNET);
        AddressChecker addressChecker = new AddressChecker(dexes);
        rewardResolverMock = new RewardResolverMock(4019);
        swapRouter = SWAP_ROUTER_BASE_MAINNET;
        FeeAccount feeAccountImpl = new FeeAccount();
        ERC1967Proxy proxy = new ERC1967Proxy(address(feeAccountImpl), "");
        feeAccount = FeeAccount(payable(address(proxy)));
        feeAccount.initialize(
            swapRouter,
            address(rewardResolverMock),
            treasury
        );
        LiquidityLocker liquidityLocker = new LiquidityLocker(address(0));
        feeAccount.setLiquidityLocker(address(liquidityLocker));
        rewardResolverMock.setFeeAccount(address(feeAccount));

        LockManager lockManagerImpl = new LockManager();
        LockPositionsNFT lockPositionsNFTImpl = new LockPositionsNFT();
        vm.startPrank(OWNER);
        memeCoin = new BurnableToken();
        address clone = Clones.clone(address(memeCoin));
        memeCoin = BurnableToken(payable(clone));
        memeCoin.initialize(
            "Test",
            "TST",
            "",
            address(addressChecker),
            false,
            OWNER,
            address(feeAccount),
            address(lockManagerImpl),
            address(lockPositionsNFTImpl)
        );

        memeCoin.setLaunched();
        memeCoin.transfer(address(this), memeCoin.balanceOf(OWNER));
        vm.stopPrank();

        console2.log("memeCoin address:", address(memeCoin));
        console2.log(
            "memeCoin balance this:",
            memeCoin.balanceOf(address(this))
        );
        address(feeAccount).call{value: 1 ether}("");

        address bondingCurveStorageAdress = address(bondingCurvesStorage);
        liquidityMigrator = new LiquidityMigrator(
            payable(address(feeAccount)),
            POSITION_MANAGER_BASE_MAINNET,
            FACTORY_BASE_MAINNET,
            WETH_BASE_MAINNET,
            address(liquidityLocker),
            bondingCurveStorageAdress
        );
        liquidityLocker.setLiquidityMigrator(address(liquidityMigrator));
        feeAccount.setLiquidityMigrator(address(liquidityMigrator));
    }

    modifier mainnetOnly() {
        if (
            block.chainid == 1 ||
            block.chainid == 8453 ||
            block.chainid == 84532 ||
            block.chainid == 11155111
        ) {
            _;
        }
    }

    function testLiquidity() public mainnetOnly {
        // Track total liquidity
        uint128 liquidity;

        address uniBondingCurvesStorage = liquidityMigrator
            .getBondingCurveStorage();
        console2.log(
            "bondingfactory balance before:",
            uniBondingCurvesStorage.balance
        );
        uniBondingCurvesStorage.call{value: 10 ether}("");
        memeCoin.transfer(uniBondingCurvesStorage, memeCoinAmount);
        vm.startPrank(uniBondingCurvesStorage);
        memeCoin.approve(
            address(liquidityMigrator),
            memeCoin.balanceOf(uniBondingCurvesStorage)
        );
        (
            uint256 tokenId,
            uint128 liquidityDelta,
            uint256 amount0,
            uint256 amount1,
            address locker
        ) = liquidityMigrator.createPoolAndLockLiquidity{
                value: wethAMount + LOCK_FLAT_FEE
            }(payable(address(memeCoin)), memeCoinAmount);
        vm.stopPrank();
        liquidity += liquidityDelta;
        address POSITION_MANAGER_BASE = 0x827922686190790b37229fd06084350E74485b72;
        IERC721 lpNft = IERC721(POSITION_MANAGER_BASE);
        console2.log("--- Mint new position ---");
        console2.log(
            "bondingfactory balance after:",
            uniBondingCurvesStorage.balance
        );
        console2.log("token id", tokenId);
        console2.log("liquidity", liquidity);
        console2.log("amount 0", amount0);
        console2.log("amount 1", amount1);
        console2.log("locker", locker);
        console2.log(
            "balance memeCoin this",
            memeCoin.balanceOf(address(this))
        );
        console2.log("balance weth this", weth.balanceOf(address(this)));
        console2.log("ownerOf nft", lpNft.ownerOf(tokenId));
        vm.startPrank(uniBondingCurvesStorage);
        address pool = ICLFactory(FACTORY_BASE_MAINNET).getPool(
            WETH_BASE_MAINNET,
            address(memeCoin),
            2000
        );
        ICLPool(pool).collect(
            uniBondingCurvesStorage,
            TickMath.MIN_TICK,
            TickMath.MAX_TICK,
            type(uint128).max,
            type(uint128).max
        );
        vm.stopPrank();
    }

    function testReward() public mainnetOnly {
        testLiquidity();
        rewardResolverMock.setState(RewardResolverMock.State.WAITING);
        rewardResolverMock.setWinner(address(memeCoin));
        rewardResolverMock.fulfillRequest(
            bytes32(uint256(0)),
            abi.encode(address(memeCoin)),
            ""
        );
        console2.log(
            "rewardResolverMock state:",
            uint256(rewardResolverMock.getState())
        );
        console2.log("eth balance feeAccount:", address(feeAccount).balance);
        console2.log(
            "weth balance feeAccount:",
            weth.balanceOf(address(feeAccount))
        );
        FeeAccount.TokenRefferences memory tokenRefferences = feeAccount
            .getCompetingTokenRefferences(address(memeCoin));
        (uint160 sqrtPriceX96Start, int24 tickStart, , , , ) = tokenRefferences
            .pool
            .slot0();
        console2.log("start sqrtPriceX96:", sqrtPriceX96Start);
        console2.log("start tick:", tickStart);
        console2.log(
            "start balance treasury:",
            address(feeAccount.treasury()).balance
        );
        console2.log("start balance feeAccount:", address(feeAccount).balance);
        feeAccount.performUpkeep("");
        (uint160 sqrtPriceX96End, int24 tickEnd, , , , ) = tokenRefferences
            .pool
            .slot0();
        console2.log("end sqrtPriceX96:", sqrtPriceX96End);
        console2.log("end tick:", tickEnd);
        console2.log(
            "end balance treasury:",
            address(feeAccount.treasury()).balance
        );
        console2.log("end balance feeAccount:", address(feeAccount).balance);
        assertEq(
            uint256(rewardResolverMock.getState()),
            uint256(RewardResolverMock.State.OPEN)
        );
        if (address(weth) > address(memeCoin)) {
            assertGt(tickEnd, tickStart);
        } else {
            assertLt(tickEnd, tickStart);
        }
        assertEq(0, memeCoin.balanceOf(address(feeAccount)));
        assertEq(0, address(feeAccount).balance);
        assertGt(address(feeAccount.treasury()).balance, 0);
    }

    function testCollectFeesOk() external {
        testLiquidity();

        FeeAccount.TokenRefferences memory tokenRefferences = feeAccount
            .getCompetingTokenRefferences(address(memeCoin));
        uint256 amountIn = 10 ether;
        weth.deposit{value: amountIn}();
        weth.approve(swapRouter, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(memeCoin),
                tickSpacing: tokenRefferences.pool.tickSpacing(),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        ISwapRouter(swapRouter).exactInputSingle(params);

        memeCoin.approve(swapRouter, memeCoin.balanceOf(address(this)));
        params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(memeCoin),
            tokenOut: address(weth),
            tickSpacing: tokenRefferences.pool.tickSpacing(),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: memeCoin.balanceOf(address(this)),
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        ISwapRouter(swapRouter).exactInputSingle(params);
        uint256 startingBalanceUser = weth.balanceOf(USER);
        address treasuryAddress = feeAccount.treasury();
        uint256 startingBalanceTreasury = weth.balanceOf(treasuryAddress);
        uint256 startingDividends = address(memeCoin).balance;

        vm.prank(USER);
        feeAccount.collectFeesAndDistribute(payable(address(memeCoin)));

        ILockManager lockManager = memeCoin.lockManager();
        console2.log("is meme gt weth?", address(memeCoin) > address(weth));

        assertTrue(address(lockManager) != address(0));
        assertGt(memeCoin.balanceOf(address(lockManager)), 0);
        assertGt(lockManager.positionsNFT().balanceOf(OWNER), 0);
        assertGt(weth.balanceOf(treasuryAddress), startingBalanceTreasury);
        assertGt(address(memeCoin).balance, startingDividends);
    }

    function testCollectFeesNoTreasuryAmount() public {
        testLiquidity();

        FeeAccount.TokenRefferences memory tokenRefferences = feeAccount
            .getCompetingTokenRefferences(address(memeCoin));
        uint256 amountIn = 500;
        weth.deposit{value: amountIn}();
        weth.approve(swapRouter, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(memeCoin),
                tickSpacing: tokenRefferences.pool.tickSpacing(),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        ISwapRouter(swapRouter).exactInputSingle(params);

        memeCoin.approve(swapRouter, memeCoin.balanceOf(address(this)));
        params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(memeCoin),
            tokenOut: address(weth),
            tickSpacing: tokenRefferences.pool.tickSpacing(),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        ISwapRouter(swapRouter).exactInputSingle(params);
        uint256 startingLockingRewards = memeCoin.balanceOf(address(memeCoin));
        uint256 startingOwnerRewards = memeCoin.balanceOf(OWNER);
        uint256 startingBalanceUser = weth.balanceOf(USER);
        address treasuryAddress = feeAccount.treasury();
        uint256 startingBalanceTreasury = weth.balanceOf(treasuryAddress);
        uint256 startingDividends = address(memeCoin).balance;
        uint256 startingFeeAccountWethBalance = weth.balanceOf(
            address(feeAccount)
        );
        uint256 startingFeeAccountTokenBalance = memeCoin.balanceOf(
            address(feeAccount)
        );

        vm.prank(USER);
        feeAccount.collectFeesAndDistribute(payable(address(memeCoin)));

        console2.log("is meme gt weth?", address(memeCoin) > address(weth));

        assertTrue(address(memeCoin.lockManager()) == address(0));
        assertEq(memeCoin.balanceOf(address(memeCoin)), startingLockingRewards);
        assertEq(memeCoin.balanceOf(address(OWNER)), startingOwnerRewards);
        assertEq(weth.balanceOf(USER), startingBalanceUser);
        assertEq(weth.balanceOf(treasuryAddress), startingBalanceTreasury);
        assertEq(address(memeCoin).balance, startingDividends);
        assertGt(
            weth.balanceOf(address(feeAccount)),
            startingFeeAccountWethBalance
        );
        assertGt(
            memeCoin.balanceOf(address(feeAccount)),
            startingFeeAccountTokenBalance
        );
        assertGt(feeAccount.accummulatedWethAmounts(address(memeCoin)), 0);
    }

    function testCollectFeesAccumulatedWethAmount() external {
        testCollectFeesNoTreasuryAmount();

        FeeAccount.TokenRefferences memory tokenRefferences = feeAccount
            .getCompetingTokenRefferences(address(memeCoin));
        uint256 amountIn = 1 ether;
        weth.deposit{value: amountIn}();
        weth.approve(swapRouter, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(memeCoin),
                tickSpacing: tokenRefferences.pool.tickSpacing(),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        ISwapRouter(swapRouter).exactInputSingle(params);

        memeCoin.approve(swapRouter, memeCoin.balanceOf(address(this)));
        params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(memeCoin),
            tokenOut: address(weth),
            tickSpacing: tokenRefferences.pool.tickSpacing(),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: memeCoin.balanceOf(address(this)),
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        ISwapRouter(swapRouter).exactInputSingle(params);
        uint256 startingBalanceUser = weth.balanceOf(USER);
        address treasuryAddress = feeAccount.treasury();
        uint256 startingBalanceTreasury = weth.balanceOf(treasuryAddress);
        uint256 startingDividends = address(memeCoin).balance;

        vm.prank(USER);
        feeAccount.collectFeesAndDistribute(payable(address(memeCoin)));

        ILockManager lockManager = memeCoin.lockManager();
        console2.log("is meme gt weth?", address(memeCoin) > address(weth));

        assertTrue(address(lockManager) != address(0));
        assertGt(memeCoin.balanceOf(address(lockManager)), 0);
        assertGt(lockManager.positionsNFT().balanceOf(OWNER), 0);
        assertGt(weth.balanceOf(treasuryAddress), startingBalanceTreasury);
        assertGt(address(memeCoin).balance, startingDividends);
        assertEq(memeCoin.balanceOf(address(feeAccount)), 0);
        assertEq(feeAccount.accummulatedWethAmounts(address(memeCoin)), 0);
    }
}
