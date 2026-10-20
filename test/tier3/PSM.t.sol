// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from
    "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";
import {PegStabilityModule} from
    "../../src/tier3/PegStabilityModule.sol";

contract PSMTest is Test {
    MockUSDC internal collateral;
    MockUSDC internal quote;
    SimpleStablecoin internal stable;
    Vault internal vault;
    PegStabilityModule internal psm;

    address internal alice = makeAddr("alice");

    function setUp() public {
        collateral = new MockUSDC();

        // 第二个独立实例，模拟另一种美元稳定币。
        quote = new MockUSDC();

        stable = new SimpleStablecoin(address(this));
        vault = new Vault(collateral, stable);

        stable.grantRole(stable.MINTER_ROLE(), address(vault));

        // sUSD 通过正常抵押流程产生。
        collateral.faucet(address(this), 10_000e6);
        collateral.approve(address(vault), 10_000e6);
        vault.deposit(10_000e6);

        psm = new PegStabilityModule(
            address(quote), address(stable)
        );

        // 为 PSM 准备两种代币库存。
        stable.transfer(address(psm), 5_000e6);
        quote.faucet(address(psm), 5_000e6);

        // 为用户准备交易资金。
        stable.transfer(alice, 1_000e6);
        quote.faucet(alice, 1_000e6);
    }

    function test_SwapQuoteForStable() public {
        vm.startPrank(alice);
        quote.approve(address(psm), 100e6);
        psm.swapToStable(100e6);
        vm.stopPrank();

        assertEq(quote.balanceOf(alice), 900e6);
        assertEq(stable.balanceOf(alice), 1_100e6);

        assertEq(quote.balanceOf(address(psm)), 5_100e6);
        assertEq(stable.balanceOf(address(psm)), 4_900e6);
    }

    function test_SwapStableForQuote() public {
        vm.startPrank(alice);
        stable.approve(address(psm), 100e6);
        psm.swapToQuote(100e6);
        vm.stopPrank();

        assertEq(stable.balanceOf(alice), 900e6);
        assertEq(quote.balanceOf(alice), 1_100e6);

        assertEq(stable.balanceOf(address(psm)), 5_100e6);
        assertEq(quote.balanceOf(address(psm)), 4_900e6);
    }

    function test_RoundTripPreservesBacking() public {
        vm.startPrank(alice);

        quote.approve(address(psm), 100e6);
        psm.swapToStable(100e6);

        stable.approve(address(psm), 100e6);
        psm.swapToQuote(100e6);

        vm.stopPrank();

        assertEq(stable.balanceOf(alice), 1_000e6);
        assertEq(quote.balanceOf(alice), 1_000e6);

        assertEq(stable.balanceOf(address(psm)), 5_000e6);
        assertEq(quote.balanceOf(address(psm)), 5_000e6);

        // 交换没有新增 sUSD，也没有动用原金库的抵押品。
        assertEq(stable.totalSupply(), 10_000e6);
        assertEq(vault.totalCollateral(), 10_000e6);
    }

    function test_RevertsWithoutApproval() public {
        vm.startPrank(alice);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(psm),
                uint256(0),
                uint256(100e6)
            )
        );

        psm.swapToStable(100e6);
        vm.stopPrank();
    }

    function test_RevertsWhenLiquidityInsufficient() public {
        // 用户有足够输入代币，但 PSM 只有 5,000 sUSD。
        quote.faucet(alice, 6_000e6);

        vm.startPrank(alice);
        quote.approve(address(psm), 6_000e6);

        vm.expectRevert(
            PegStabilityModule.InsufficientLiquidity.selector
        );
        psm.swapToStable(6_000e6);

        vm.stopPrank();

        // 兑换失败，没有扣走用户的输入代币。
        assertEq(quote.balanceOf(alice), 7_000e6);
        assertEq(stable.balanceOf(address(psm)), 5_000e6);
    }

    function test_ZeroAmountReverts() public {
        vm.expectRevert(PegStabilityModule.ZeroAmount.selector);
        psm.swapToStable(0);

        vm.expectRevert(PegStabilityModule.ZeroAmount.selector);
        psm.swapToQuote(0);
    }
}