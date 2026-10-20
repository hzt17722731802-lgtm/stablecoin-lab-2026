// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from
    "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from
    "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from
    "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Lab PSM: fee-free, inventory-funded, fixed 1:1 swaps.
/// @dev Supports standard tokens with matching decimals.
///      Inventory is provided by transferring tokens into this contract.
contract PegStabilityModule is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable quote;
    IERC20 public immutable stable;

    error InvalidPair();
    error DecimalsMismatch();
    error ZeroAmount();
    error InsufficientLiquidity();

    event Swap(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amount
    );

    constructor(address quote_, address stable_) {
        if (
            quote_ == address(0) || stable_ == address(0)
                || quote_ == stable_
        ) {
            revert InvalidPair();
        }

        if (
            IERC20Metadata(quote_).decimals()
                != IERC20Metadata(stable_).decimals()
        ) {
            revert DecimalsMismatch();
        }

        quote = IERC20(quote_);
        stable = IERC20(stable_);
    }

    // 外部稳定币 -> sUSD
    function swapToStable(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        if (stable.balanceOf(address(this)) < amount) {
            revert InsufficientLiquidity();
        }

        quote.safeTransferFrom(msg.sender, address(this), amount);
        stable.safeTransfer(msg.sender, amount);

        emit Swap(
            msg.sender, address(quote), address(stable), amount
        );
    }

    // sUSD -> 外部稳定币
    function swapToQuote(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        if (quote.balanceOf(address(this)) < amount) {
            revert InsufficientLiquidity();
        }

        stable.safeTransferFrom(msg.sender, address(this), amount);
        quote.safeTransfer(msg.sender, amount);

        emit Swap(
            msg.sender, address(stable), address(quote), amount
        );
    }
}