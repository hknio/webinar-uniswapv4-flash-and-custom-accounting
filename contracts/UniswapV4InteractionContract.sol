// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Fees} from "./libraries/Fees.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

contract UniswapV4InteractionContract is IUnlockCallback {
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using SafeCast for int256;
    using SafeCast for int128;

    address public manager;
    address public owner;
    address public hook;

    constructor(address _manager) {
        require(_manager != address(0), "Pool manager can not be zero address.");
        manager = _manager;
        owner = msg.sender;
    }

    function poolManager() public view returns (IPoolManager) {
        return IPoolManager(manager);
    }

    function setHook(address hookAddress) public {
        hook = hookAddress;
    }

    function addLiquidity(PoolKey calldata key, int24 tickLower, int24 tickUpper, int256 liquidityDelta) external {
        bytes memory data = abi.encodeWithSelector(
            this.addLiquidityCallback.selector,
            key,
            tickLower,
            tickUpper,
            liquidityDelta,
            msg.sender 
        );
        poolManager().unlock(data);
    }

    function removeLiquidity(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDeltaToRemove
    ) external {
        require(liquidityDeltaToRemove > 0, "Liquidity delta must be positive");

        bytes memory data = abi.encodeWithSelector(
            this.removeLiquidityCallback.selector,
            key,
            tickLower,
            tickUpper,
            -liquidityDeltaToRemove, 
            msg.sender
        );
        poolManager().unlock(data);
    }

    function addLiquidityAndSwap(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta,
        bool zeroForOne,
        int256 amountSpecified
    ) external {
        bytes memory data = abi.encodeWithSelector(
            this.addLiquidityAndSwapCallback.selector,
            key,
            tickLower,
            tickUpper,
            liquidityDelta,
            zeroForOne,
            amountSpecified,
            msg.sender
        );
        poolManager().unlock(data);
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == manager, "Only manager can call this function");
        (bool success, bytes memory result) = address(this).call(data);
        if (success) return result;
        if (result.length == 0) revert("unlockCallback failed");
        assembly {
            revert(add(result, 32), mload(result))
        }
    }

    function addLiquidityCallback(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta,
        address caller
    ) external returns (bytes memory) {
        require(msg.sender == address(this), "Only self-call allowed");

        IERC20(Currency.unwrap(key.currency0)).approve(address(manager), 1e18);
        IERC20(Currency.unwrap(key.currency1)).approve(address(manager), 1e18);

        (BalanceDelta delta,) = poolManager().modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: 0}),
            new bytes(0)
        );

        uint256 amount0 = uint256(uint128(-delta.amount0()));
        uint256 amount1 = uint256(uint128(-delta.amount1()));

        transferAndSettle(key.currency0, caller, amount0);
        transferAndSettle(key.currency1, caller, amount1);

        return "";
    }

    function removeLiquidityCallback(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        int256 negativeLiquidityDelta,
        address caller
    ) external returns (bytes memory) {
        require(msg.sender == address(this), "Only self-call allowed");

        (BalanceDelta delta,) = poolManager().modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: negativeLiquidityDelta, salt: 0}),
            new bytes(0)
        );

        uint256 amount0 = uint256(uint128(delta.amount0()));
        uint256 amount1 = uint256(uint128(delta.amount0()));

        transferToCaller(key.currency0, caller, amount0);
        transferToCaller(key.currency1, caller, amount1);

        return "";
    }

    function addLiquidityAndSwapCallback(
        PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta,
        bool zeroForOne,
        int256 amountSpecified,
        address caller
    ) external returns (bytes memory) {
        require(msg.sender == address(this), "Only self-call allowed");

        (BalanceDelta liquidityDeltaResult, ) = poolManager().modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: 0}),
            new bytes(0)
        );

        BalanceDelta swapDelta = poolManager().swap(
            key,
            IPoolManager.SwapParams({zeroForOne: zeroForOne, amountSpecified: amountSpecified, sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1}),
            new bytes(0)
        );

        if (liquidityDeltaResult.amount0() < 0) {
            uint256 amount0 = uint256(uint128(-liquidityDeltaResult.amount0()));
            transferAndSettle(key.currency0, caller, amount0);
        }
        if (liquidityDeltaResult.amount1() < 0) {
            uint256 amount1 = uint256(uint128(-liquidityDeltaResult.amount1()));
            transferAndSettle(key.currency1, caller, amount1);
        }

        if (swapDelta.amount0() < 0) {
            uint256 amount0 = uint256(uint128(-swapDelta.amount0()));
            transferAndSettle(key.currency0, caller, amount0);
        } else if (swapDelta.amount0() > 0) {
            uint256 amount0 = uint256(uint128(swapDelta.amount0()));
            transferToCaller(key.currency0, caller, amount0);
        }

        if (swapDelta.amount1() < 0) {
            uint256 amount1 = uint256(uint128(-swapDelta.amount1()));
            transferAndSettle(key.currency1, caller, amount1);
        } else if (swapDelta.amount1() > 0) {
            uint256 amount1 = uint256(uint128(swapDelta.amount1()));
            transferToCaller(key.currency1, caller, amount1);
        }

        return "";
    }

    function setManager(address newManager) external {
        require(msg.sender == owner || msg.sender == address(this), "Not authorized");
        manager = newManager;
    }

    function transferAndSettle(Currency currency, address from, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(Currency.unwrap(currency)).transferFrom(from, address(this), amount);
        IERC20(Currency.unwrap(currency)).approve(address(poolManager()), amount);
        currency.settle(poolManager(), address(this), amount, false);
    }

    function transferToCaller(Currency currency, address to, uint256 amount) internal {
        if (amount == 0) return;
        currency.take(poolManager(), to, amount, false);
    }

    event DebugDelta(string label, int128 delta);
}
