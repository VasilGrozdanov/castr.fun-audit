// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {console} from "forge-std/console.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20, IERC20Errors} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721Enumerable as IERC721} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import {IVotingEscrow} from "src/external/IVotingEscrow.sol";
import {IVoter} from "src/external/IVoter.sol";
import {IGauge} from "src/external/IGauge.sol";
import {IV2Pool} from "src/external/IV2Pool.sol";
import {IV2Router} from "src/external/IV2Router.sol";
import {IFactoryRegistry} from "src/external/IFactoryRegistry.sol";

import {V2PoolLauncher, IV2PoolLauncher} from "src/extensions/v2/V2PoolLauncher.sol";
import {V2LockerFactory, IV2LockerFactory} from "src/extensions/v2/V2LockerFactory.sol";
import {V2Locker, IV2Locker} from "src/extensions/v2/V2Locker.sol";

import {CLPoolLauncher, ICLPoolLauncher} from "src/extensions/cl/CLPoolLauncher.sol";
import {CLLockerFactory} from "src/extensions/cl/CLLockerFactory.sol";
import {CLLocker, ICLLocker} from "src/extensions/cl/CLLocker.sol";

import {IPoolLauncher} from "src/interfaces/IPoolLauncher.sol";
import {ILockerFactory} from "src/interfaces/ILockerFactory.sol";
import {ILocker} from "src/interfaces/ILocker.sol";

import {TickMath} from "src/libraries/TickMath.sol";

import {IV2Factory} from "src/external/IV2Factory.sol";
import {ICLPool} from "src/external/ICLPool.sol";
import {ICLFactory} from "src/external/ICLFactory.sol";
import {IVotingEscrow} from "src/external/IVotingEscrow.sol";
import {INonfungiblePositionManager as INfpm} from "src/external/INonfungiblePositionManager.sol";

import {Router} from "./mocks/Router.sol";
import {MockNFPM} from "./mocks/MockNFPM.sol";
import {MockVoter} from "./mocks/MockVoter.sol";
import {MockV2Factory} from "./mocks/MockV2Factory.sol";
import {MockCLFactory} from "./mocks/MockCLFactory.sol";
import {TestDeployCL, DeployCLFixture} from "./utils/TestDeployCL.sol";
import {TestDeployV2, DeployV2Fixture} from "./utils/TestDeployV2.sol";
import {TestConstants} from "./utils/TestConstants.sol";
import {BasicERC20} from "./utils/BasicERC20.sol";
import {TestOwner} from "./utils/TestOwner.sol";
import {Users} from "./utils/Users.sol";

contract BaseFixture is Test, TestConstants {
    using stdStorage for StdStorage;

    TestDeployCL public deployCL;
    DeployCLFixture.DeploymentParameters public deployCLParams;

    TestDeployV2 public deployV2;
    TestDeployV2.DeploymentParameters public deployV2Params;

    // poolLauncher contracts
    V2PoolLauncher public v2PoolLauncher;
    V2LockerFactory public v2LockerFactory;

    // CL PoolLauncher contracts
    CLLockerFactory public clLockerFactory;
    CLPoolLauncher public clPoolLauncher;

    // poolLauncher dependencies
    address public nfpManager;
    address public clFactory;
    address public v2Factory;
    address public v2Router;
    address public voter;

    ///  @dev usdc token whitelisted in the poolLauncher
    IERC20 public usdc;
    ///  @dev token that can be used for testing
    IERC20 public token;

    Users internal users;

    function setUp() public virtual {
        createUsers();
        setUpToken();
        setUpUsdc();
        deployPoolLauncher();
    }

    function setUpToken() internal virtual {
        token = IERC20(new BasicERC20("Token", "TKN", 100 ether));
    }

    function setUpUsdc() internal virtual {
        usdc = IERC20(new BasicERC20("USDC", "USDC", 100 ether));
    }

    function deployDependencies() internal virtual {
        voter = address(new MockVoter());
        nfpManager = address(new MockNFPM());
        clFactory = address(new MockCLFactory());
        v2Factory = address(new MockV2Factory());
        v2Router = address(makeAddr("router"));
    }

    function deployPoolLauncher() internal virtual {
        deployDependencies();

        deployCLParams = DeployCLFixture.DeploymentParameters({
            owner: users.owner,
            voter: voter,
            nfpManager: nfpManager,
            outputFilename: "test.json"
        });
        deployCL = new TestDeployCL({_params_: deployCLParams});
        stdstore.target(address(deployCL)).sig("deployer()").checked_write(users.deployer);
        deployCL.run();

        clLockerFactory = deployCL.clLockerFactory();
        clPoolLauncher = deployCL.clPoolLauncher();

        deployV2Params = DeployV2Fixture.DeploymentParameters({
            v2Factory: v2Factory,
            v2Router: v2Router,
            voter: voter,
            owner: users.owner,
            outputFilename: "test.json"
        });
        deployV2 = new TestDeployV2({_params_: deployV2Params});
        stdstore.target(address(deployV2)).sig("deployer()").checked_write(users.deployer);
        deployV2.run();

        v2PoolLauncher = deployV2.v2PoolLauncher();
        v2LockerFactory = deployV2.v2LockerFactory();

        vm.startPrank(users.owner);
        clPoolLauncher.addPairableToken({_token: address(usdc)});
        v2PoolLauncher.addPairableToken({_token: address(usdc)});
        vm.stopPrank();
    }

    function createUser() internal returns (address payable user) {
        user = payable(new TestOwner());
        vm.deal({account: user, newBalance: TOKEN_1 * 1_000});
    }

    function createUsers() internal {
        users = Users({
            owner: createUser(),
            alice: createUser(),
            bob: createUser(),
            charlie: createUser(),
            deployer: createUser(),
            deployer2: createUser()
        });
    }

    // Allow for receiving ERC721 tokens in tests
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function predictV2PoolAddress(address tokenA, address tokenB, bool stable) internal view returns (address pool) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, stable));
        pool = Clones.predictDeterministicAddress(IV2Factory(v2Factory).implementation(), salt, v2Factory);
    }

    function predictCLPoolAddress(address tokenA, address tokenB, int24 tickSpacing, address factory)
        internal
        view
        returns (address pool)
    {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 salt = keccak256(abi.encode(token0, token1, tickSpacing));
        pool = Clones.predictDeterministicAddress(ICLFactory(factory).poolImplementation(), salt, factory);
    }

    function predictLockerAddress(address lockerFactory, uint8 nonce) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"d6", // list prefix
                            hex"94", // address length
                            lockerFactory,
                            nonce // nonce
                        )
                    )
                )
            )
        );
    }

    /// @dev CL Helpers
    function encodePriceSqrt(uint256 reserve1, uint256 reserve0) public pure returns (uint160) {
        reserve1 = reserve1 * 2 ** 192;
        uint256 division = reserve1 / reserve0;
        uint256 sqrtX96 = sqrt(division);

        return toUint160(sqrtX96);
    }

    function toUint160(uint256 y) internal pure returns (uint160 z) {
        require((z = uint160(y)) == y);
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function getMinTick(int24 tickSpacing) internal pure returns (int24) {
        return (-887272 / tickSpacing) * tickSpacing;
    }

    function getMaxTick(int24 tickSpacing) internal pure returns (int24) {
        return (887272 / tickSpacing) * tickSpacing;
    }

    function mintLP(
        address token0,
        address token1,
        int24 tickSpacing,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1,
        address recipient
    ) internal returns (uint256) {
        IERC20(token0).approve({spender: address(nfpManager), value: amount0});
        IERC20(token1).approve({spender: address(nfpManager), value: amount1});

        //slither-disable-next-line unused-return
        (uint256 lp,,,) = INfpm(nfpManager).mint({
            params: INfpm.MintParams({
                token0: token0,
                token1: token1,
                tickSpacing: tickSpacing,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: recipient,
                deadline: block.timestamp,
                sqrtPriceX96: 0
            })
        });

        return lp;
    }

    function computeCLPositionKey(address owner, int24 tickLower, int24 tickUpper) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, tickLower, tickUpper));
    }
}
