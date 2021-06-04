// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";

abstract contract GlobalsAndUtility is ERC20 {

    uint32 public constant minBurnAmount = 5000000;
    uint256 public constant INTEREST_INTERVAL = 7 days;
    uint256 public constant INTEREST_MULTIPLIER = 1612;
    uint256 public constant MINIMUM_INTEREST_DENOMINATOR = 1612;
    uint256 public constant BURN_TIME_UNIT = 1 days;
    uint256 public constant CYANIDE_PER_CYAN = 1000000000000; // 1 CYAN = 1e12 CYANIDE

}
