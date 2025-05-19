// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BaseHook} from "../../../contracts/BaseHook.sol";
import {HookFee} from "../../../contracts/HookFee.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract HookFeeImplementation is HookFee {
    constructor(IPoolManager _poolManager, HookFee addressToEtch) HookFee(_poolManager) {
        Hooks.validateHookPermissions(addressToEtch, getHookPermissions());
    }

    function validateHookAddress(BaseHook _this) internal pure override {}
}
