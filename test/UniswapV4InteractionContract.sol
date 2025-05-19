
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {UniswapV4InteractionContract} from "../contracts/UniswapV4InteractionContract.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

contract UniswapV4InteractionContractTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    UniswapV4InteractionContract public uniswapV4InteractionContract;
    MockERC20 public token0;
    MockERC20 public token1;

    function setUp() public {
        deployFreshManagerAndRouters();
        uniswapV4InteractionContract = new UniswapV4InteractionContract(address(manager));

        token0 = new MockERC20("Token0", "T0", 18);
        token1 = new MockERC20("Token1", "T1", 18);

        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        manager.initialize(key, TickMath.getSqrtPriceAtTick(0), "");

        token0.approve(address(manager), type(uint256).max);
        token1.approve(address(manager), type(uint256).max);
    }

    function testPerformAddLiquidity() public {
        address user = address(this);
        uint256 initialAmount = 1e18;

        int24 tickLower = -120;
        int24 tickUpper = 120;

        token0.mint(user, initialAmount);
        token1.mint(user, initialAmount);

        token0.approve(address(uniswapV4InteractionContract), initialAmount);
        token1.approve(address(uniswapV4InteractionContract), initialAmount);

        vm.prank(address(uniswapV4InteractionContract));
        token0.approve(address(manager), type(uint256).max);
        vm.prank(address(uniswapV4InteractionContract));
        token1.approve(address(manager), type(uint256).max);

        uniswapV4InteractionContract.addLiquidity(key, tickLower, tickUpper, int256(initialAmount));

        PoolId poolId = key.toId();
        uint128 liquidity = manager.getLiquidity(poolId);

        assertGt(liquidity, 0, "Liquidity should have been added to the pool");

        emit log_named_uint("Liquidity in pool after addLiquidity", liquidity);
    }

    function testPerformRemoveLiquidity() public {
        address user = address(this);
        uint256 initialAmount = 1e18;

        int24 tickLower = -120;
        int24 tickUpper = 120;
        PoolId poolId = key.toId();

        // --- 1. Mint and approve tokens ---
        token0.mint(user, initialAmount);
        token1.mint(user, initialAmount);

        token0.approve(address(uniswapV4InteractionContract), initialAmount);
        token1.approve(address(uniswapV4InteractionContract), initialAmount);

        // Approve manager from the interaction contract
        vm.prank(address(uniswapV4InteractionContract));
        token0.approve(address(manager), type(uint256).max);
        vm.prank(address(uniswapV4InteractionContract));
        token1.approve(address(manager), type(uint256).max);

        
        // --- 2. Add liquidity ---
        uniswapV4InteractionContract.addLiquidity(key, tickLower, tickUpper, int256(initialAmount));

        uint128 liquidityBefore = manager.getLiquidity(poolId);
        assertGt(liquidityBefore, 0, "Liquidity should be added before removal");

        emit log_named_uint("Liquidity liquidityBefore removal", liquidityBefore);


        // --- 3. Capture balances before ---
        uint256 token0Before = token0.balanceOf(user);
        uint256 token1Before = token1.balanceOf(user);

        // --- 4. Remove liquidity (half) ---
        uniswapV4InteractionContract.removeLiquidity(
            key,
            tickLower,
            tickUpper,
            int256(initialAmount / 2)
        );

        // --- 5. Assert liquidity decreased ---
        uint128 liquidityAfter = manager.getLiquidity(poolId);
        assertLt(liquidityAfter, liquidityBefore, "Liquidity should have decreased");

        // --- 6. Assert tokens returned ---
        uint256 token0After = token0.balanceOf(user);
        uint256 token1After = token1.balanceOf(user);

        assertGt(token0After, token0Before, "User should receive back token0");
        assertGt(token1After, token1Before, "User should receive back token1");

        emit log_named_uint("Liquidity after removal", liquidityAfter);
        emit log_named_uint("Token0 returned", token0After - token0Before);
        emit log_named_uint("Token1 returned", token1After - token1Before);
    }

    function testAddLiquidityAndSwap() public {
        address user = address(this);
        uint256 liquidityAmount = 1e18;
        int256 swapAmount = 1000;

        int24 tickLower = -120;
        int24 tickUpper = 120;
        PoolId poolId = key.toId();

        // --- 1. Mint tokens ---
        token0.mint(user, liquidityAmount);
        token1.mint(user, liquidityAmount); // для страховки, якщо swap вимагає додати обидва токени

        // --- 2. Approve interaction contract ---
        token0.approve(address(uniswapV4InteractionContract), liquidityAmount);
        token1.approve(address(uniswapV4InteractionContract), liquidityAmount);

        // --- 3. Approve manager from interaction contract (for settle) ---
        vm.prank(address(uniswapV4InteractionContract));
        token0.approve(address(manager), type(uint256).max);
        vm.prank(address(uniswapV4InteractionContract));
        token1.approve(address(manager), type(uint256).max);

        // --- 4. Record balances before swap ---
        uint256 token0Before = token0.balanceOf(user);
        uint256 token1Before = token1.balanceOf(user);

        // --- 5. Call addLiquidityAndSwap ---
        uniswapV4InteractionContract.addLiquidityAndSwap(
            key,
            tickLower,
            tickUpper,
            int256(liquidityAmount),
            true,           // swap direction: token0 → token1
            swapAmount      // user wants to sell 1000 token0
        );

        // --- 6. Check liquidity exists ---
        uint128 liquidity = manager.getLiquidity(poolId);
        assertGt(liquidity, 0, "Liquidity should have been added");

        // --- 7. Check token balances changed (swap happened) ---
        uint256 token0After = token0.balanceOf(user);
        uint256 token1After = token1.balanceOf(user);

        emit log_named_uint("token0After", token0After);
        emit log_named_uint("token0Before", token0Before);

        emit log_named_uint("token1After", token1After);
        emit log_named_uint("token1Before", token1Before);
    }

}
