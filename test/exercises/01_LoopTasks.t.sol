// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title Ex2 + Ex4 — hands-on tasks: turn red into green
/// @notice Every `assertTrue(false, "TODO ...")` below is a placeholder. Write the real
///         assertion, watch the test go green, and that exercise is done.
///
///         Acceptance: make exercise (it should be red until you are finished)
///         Do not open test/Stablecoin.t.sol — it contains the answers. Write yours
///         first, and only look once you are stuck.
contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    function _depositForAlice(uint256 amount) internal {
    usdc.faucet(alice, amount);

    vm.startPrank(alice);
    usdc.approve(address(vault), amount);
    vault.deposit(amount);
    vm.stopPrank();
    }

    // ==================================================================
    // Ex2 · the decimals trap: a 6-decimal stablecoin meets 18-decimal intuition
    // ==================================================================

    /// @dev For any legitimate amount x, totalSupply() must grow by exactly x after
    ///      deposit(x). Hint: use vm.assume to rule out x == 0, and faucet alice enough
    ///      usdc first.
    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public {
    // 将输入限制在合理范围，并排除零。
    uint256 amount = uint256(raw) % 1_000_000e6;
    vm.assume(amount > 0);

    // 给测试用户 Alice 准备抵押品。
    usdc.faucet(alice, amount);

    // 记录存入前的状态。
    uint256 supplyBefore = stable.totalSupply();
    uint256 balanceBefore = stable.balanceOf(alice);
    uint256 collateralBefore = vault.totalCollateral();

    // 模拟 Alice 授权并存入。
    vm.startPrank(alice);
    usdc.approve(address(vault), amount);
    vault.deposit(amount);
    vm.stopPrank();

    // 检查供应量、个人余额和抵押品是否同步增加。
    assertEq(stable.totalSupply(), supplyBefore + amount);
    assertEq(stable.balanceOf(alice), balanceBefore + amount);
    assertEq(vault.totalCollateral(), collateralBefore + amount);
    }

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. MockUSDC has 6 decimals — 1000e18 is one billion USDC.
    ///      There is no expected answer here; the point is that you run it yourself and
    ///      read the numbers.
    function test_Ex2_DecimalsTrap() public {
    // 故意使用 18 位小数的写法。
    uint256 amount = 1000e18;

    assertEq(usdc.decimals(), 6);
    assertEq(stable.decimals(), 6);

    // 模拟水龙头可以发放足够多的抵押品。
    usdc.faucet(alice, amount);

    vm.startPrank(alice);
    usdc.approve(address(vault), amount);
    vault.deposit(amount);
    vm.stopPrank();

    // 操作成功，账面上的抵押与发行仍然匹配。
    assertEq(stable.balanceOf(alice), amount);
    assertEq(stable.totalSupply(), amount);
    assertEq(vault.totalCollateral(), stable.totalSupply());

    // 根据实际小数位，把最小单位换算成完整代币数量。
    uint256 unit = 10 ** uint256(stable.decimals());
    uint256 actualTokens = stable.balanceOf(alice) / unit;

    // 实际得到 10^15 枚，远多于原本想要的 1000 枚。
    assertEq(actualTokens, 1_000_000_000_000_000);
    assertEq(actualTokens / 1000, 1_000_000_000_000);
    }

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================
function test_Ex4_Mint_RevertsForNonMinter() public {
    bytes32 role = stable.MINTER_ROLE();

    vm.startPrank(attacker);
    vm.expectRevert(
        abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            attacker,
            role
        )
    );
    stable.mint(attacker, 100e6);
    vm.stopPrank();

    assertEq(stable.balanceOf(attacker), 0);
    assertEq(stable.totalSupply(), 0);
}

function test_Ex4_Pause_BlocksTransfers() public {
    uint256 amount = 100e6;
    _depositForAlice(amount);

    // 当前测试合约就是管理员，可以暂停。
    stable.pause();

    vm.startPrank(alice);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    stable.transfer(attacker, 10e6);
    vm.stopPrank();

    // 转账失败后，双方余额不变。
    assertEq(stable.balanceOf(alice), amount);
    assertEq(stable.balanceOf(attacker), 0);
}

function test_Ex4_Pause_BlocksRedeem() public {
    uint256 amount = 100e6;
    _depositForAlice(amount);

    stable.pause();

    vm.startPrank(alice);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    vault.redeem(amount);
    vm.stopPrank();

    // 赎回失败：币没有销毁，抵押品也没有退回。
    assertEq(stable.balanceOf(alice), amount);
    assertEq(stable.totalSupply(), amount);
    assertEq(vault.totalCollateral(), amount);
    assertEq(usdc.balanceOf(alice), 0);

    // 恢复后可以正常赎回，进一步确认阻碍来自暂停。
    stable.unpause();

    vm.prank(alice);
    vault.redeem(amount);

    assertEq(stable.balanceOf(alice), 0);
    assertEq(stable.totalSupply(), 0);
    assertEq(vault.totalCollateral(), 0);
    assertEq(usdc.balanceOf(alice), amount);
}

function test_Ex4_AttackerCannotBurnOthersBalance() public {
    uint256 amount = 100e6;
    _depositForAlice(amount);
    bytes32 role = stable.MINTER_ROLE();

    vm.startPrank(attacker);
    vm.expectRevert(
        abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector,
            attacker,
            role
        )
    );
    stable.burn(alice, 40e6);
    vm.stopPrank();

    assertEq(stable.balanceOf(alice), amount);
    assertEq(stable.totalSupply(), amount);
    assertEq(vault.totalCollateral(), amount);
}

function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance() public {
    uint256 amount = 100e6;
    _depositForAlice(amount);

    // Alice 没有授权金库花费她的 sUSD。
    assertEq(stable.allowance(alice, address(vault)), 0);

    // 模拟金库身份，直接调用代币合约的 burn。
    vm.prank(address(vault));
    stable.burn(alice, 40e6);

    assertEq(stable.balanceOf(alice), 60e6);
    assertEq(stable.totalSupply(), 60e6);

    // 这里只销毁代币，没有执行退回抵押品的流程。
    assertEq(vault.totalCollateral(), amount);
    assertEq(usdc.balanceOf(alice), 0);
}
}
