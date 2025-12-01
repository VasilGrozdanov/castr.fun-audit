// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "./BaseFixture.sol";

contract BaseForkFixture is BaseFixture {
    function parsedAddresses() internal view virtual returns (string memory) {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/test/e2e/addresses-base.json"));
        return vm.readFile(path);
    }

    function setUp() public virtual override {
        vm.createSelectFork({urlOrAlias: "base", blockNumber: 33290777});
        super.setUp();
    }

    function setUpUsdc() internal override {
        usdc = IERC20(vm.parseJsonAddress(parsedAddresses(), ".USDC"));
        deal(address(usdc), address(this), 100 ether);
    }

    function deployDependencies() internal virtual override {
        string memory addresses = parsedAddresses();
        voter = vm.parseJsonAddress(addresses, ".Voter");
        v2Router = vm.parseJsonAddress(addresses, ".V2Router");
        v2Factory = vm.parseJsonAddress(addresses, ".V2Factory");
        clFactory = vm.parseJsonAddress(addresses, ".CLFactory");
        nfpManager = vm.parseJsonAddress(addresses, ".NfpManager");
    }
}
