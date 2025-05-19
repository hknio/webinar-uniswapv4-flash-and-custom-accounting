// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {HookFee} from "../contracts/HookFee.sol";
import {HookFeeImplementation} from "./shared/implementation/HookFeeImplementation.sol";
import {UniswapV4InteractionContract} from "../contracts/UniswapV4InteractionContract.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

contract HookFeeTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint256 initialAmount = 1e18;


    UniswapV4InteractionContract public uniswapV4InteractionContract;

    HookFee public hook;
    
    MockERC20 public token0;
    MockERC20 public token1;

    int24 tickLower = -120;
    int24 tickUpper = 120;

    function setUp() public {
        deployFreshManagerAndRouters();

        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);


        HookFeeImplementation hookFee = HookFeeImplementation(
            address(uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            ))
        );

        HookFee impl = new HookFeeImplementation(manager, hookFee);

        vm.etch(address(hookFee), address(impl).code);

        hook = HookFee(address(hookFee));

        // Mint and approve tokens
        token0.mint(address(this), 1e24);
        token1.mint(address(this), 1e24);

        token0.approve(address(manager), type(uint256).max);
        token1.approve(address(manager), type(uint256).max);

        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        address user = address(this);
        
        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });

        manager.initialize(key, SQRT_PRICE_1_1, bytes(""));

        // --- 1. Mint and approve tokens ---
        token0.mint(user, initialAmount);
        token1.mint(user, initialAmount);

        token0.mint(address(manager), initialAmount);
        token1.mint(address(manager), initialAmount);

        token0.approve(address(manager), type(uint256).max);
        token1.approve(address(manager), type(uint256).max);

        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);

        
    }

    function testSwapTriggersHookAndChargesFee() public {
        IPoolManager.SwapParams memory swapParams =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -100, sqrtPriceLimitX96: SQRT_PRICE_1_2});
        PoolSwapTest.TestSettings memory testSettings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        uint256 hookBalance0Before = token0.balanceOf(address(hook));

        swapRouter.swap(key, swapParams, testSettings, ZERO_BYTES);

        uint256 hookBalance0After = token0.balanceOf(address(hook));

        assertEq(hookBalance0After - hookBalance0Before, 10);
    }
}
