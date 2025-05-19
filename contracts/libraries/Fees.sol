// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Fees {
    uint256 public constant HOOK_FEE_PERCENTAGE = 10000; // 10%
    uint256 public constant FEE_DENOMINATOR = 100000;

    /// @notice Calculates fee from a given amount using predefined constants
    /// @param amount The amount to calculate the fee from
    /// @return fee The fee to be taken (rounded down)
    function calculateFee(uint256 amount) internal pure returns (uint256) {
        return (amount * HOOK_FEE_PERCENTAGE) / FEE_DENOMINATOR;
    }
}
