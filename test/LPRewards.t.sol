// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {RToken} from "../src/RToken.sol";
import {LiquidityRewardHook} from "../src/LPRewards.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LPRewardsTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    LiquidityRewardHook hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;
    int24 tickSpacing = 60;

    address owner = makeAddr("owner");
    address lp1 = makeAddr("lp1");

    RToken rToken;
    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployAndApprovePosm(manager);

        rToken = new RToken("RToken", "RTKN", owner);
        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_REMOVE_LIQUIDITY_FLAG 
            ) ^ (0x1234 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(
            manager,            // Pool manager
            owner,              // Hook owner
            address(rToken),    // Reward token
            300000000,          // Min accumulated liquidity for reward: liquidity / 1e18
            2                   // Reward rate
        );
       
        deployCodeTo("LPRewards.sol:LiquidityRewardHook", constructorArgs, flags);
        hook = LiquidityRewardHook(flags);
        vm.prank(owner);
        rToken.setMinter(address(hook));

        // Create the pool
        key = PoolKey(
            currency0, 
            currency1, 
            3000, // fee
            60, // tick spacing
            IHooks(hook)
        );
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        vm.prank(owner);
            hook.setAllowedPool(poolId, true);

    }

    function testSetMultiplier(address lp, uint256 multiplier) public {
        vm.prank(owner);
        hook.setRewardMultiplier(lp, multiplier);
        assertEq(hook.multiplier(lp), multiplier);
    }

    function testOnlyOwnerCanSetMultiplier(address user, address lp, uint256 multiplier) public {
        vm.assume(user != owner);
        vm.prank(user);
        vm.expectRevert();
        hook.setRewardMultiplier(lp, multiplier);
    }

    function testSetMinAccLiquidityForReward(uint256 minAccLiquidityForReward) public {
        vm.prank(owner);
        hook.setMinAccLiquidityForReward(minAccLiquidityForReward);
        assertEq(hook.minAccLiquidityForReward(), minAccLiquidityForReward);
    }

    function testOnlyOwnerCanSetMinAccLiquidityForReward(address user,uint256 minAccLiquidityForReward) public {
        vm.assume(user != owner);
        vm.prank(user);
        vm.expectRevert();
        hook.setMinAccLiquidityForReward(minAccLiquidityForReward);
    }

    function testSetRewardRatePerAccLiquidity(uint256 rate) public {
        vm.prank(owner);
        hook.setRewardRatePerAccLiquidity(rate);
        assertEq(hook.rewardRatePerAccLiquidity(), rate);
    }

    function testOnlyOwnerCanSetRewardRatePerAccLiquidity(address user, uint256 rate) public {
        vm.assume(user != owner);
        vm.prank(user);
        vm.expectRevert();
        hook.setRewardRatePerAccLiquidity(rate);
    }

    function testProvideLqAndGetReward() public {
        address user = lp1;
        uint daysCount = 10;
        uint rangePercent = 5;
        uint128 liquidityAmount = 200e18;

        provideLiquidity(user, rangePercent, liquidityAmount);
        // move time
        vm.warp(block.timestamp + 86400 * daysCount);

        decreaseLiquidity(user, liquidityAmount);
        
        assertEq(rToken.balanceOf(user), 345600000);
    }

   function testProvideLqTwiceAndGetReward() public {
        address user = lp1;
        uint daysCount = 10;
        uint rangePercent = 5;
        uint128 liquidityAmount = 100e18;

        provideLiquidity(user, rangePercent, liquidityAmount);
        // in the same block, provide additional liquidity
        increaseLiquidity(user, liquidityAmount);
        // move time
        vm.warp(block.timestamp + 86400 * daysCount);

        decreaseLiquidity(user, liquidityAmount*2);
        
        assertEq(rToken.balanceOf(user), 345600000);
    }

    function testProvideLqAndRemoveInTheSameBlockNoReward() public {
        address user = lp1;
        uint rangePercent = 5;
        uint128 liquidityAmount = 200e18;

        provideLiquidity(user, rangePercent, liquidityAmount);

        decreaseLiquidity(user, liquidityAmount);
        
        assertEq(rToken.balanceOf(user), 0);
    }

    function testProvideLqAndWaitShortTimeNoReward() public {
        address user = lp1;
        uint daysCount = 1;
        uint rangePercent = 5;
        uint128 liquidityAmount = 200e18;

        provideLiquidity(user, rangePercent, liquidityAmount);
        // move time
        vm.warp(block.timestamp + 86400 * daysCount);

        decreaseLiquidity(user, liquidityAmount);
        
        assertEq(rToken.balanceOf(user), 0);
    }

    function testProvideLqGetRewardProvideLqAgainGetReward() public {
        address user = lp1;
        uint daysCount = 10;
        uint rangePercent = 5;
        uint128 liquidityAmount = 200e18;

        provideLiquidity(user, rangePercent, liquidityAmount);
        // move time
        vm.warp(block.timestamp + 86400 * daysCount);

        decreaseLiquidity(user, liquidityAmount);
        assertEq(rToken.balanceOf(user), 345600000);

        increaseLiquidity(user, liquidityAmount);
        vm.warp(block.timestamp + 86400 * daysCount);

        decreaseLiquidity(user, liquidityAmount);
        assertEq(rToken.balanceOf(user), 345600000 * 2);
    }

    function testProvideLqGetRewardWithMultiplier() public {
        address user = lp1;
        uint daysCount = 10;
        uint rangePercent = 5;
        uint128 liquidityAmount = 200e18;

        provideLiquidity(user, rangePercent, liquidityAmount);
        // move time
        vm.warp(block.timestamp + 86400 * daysCount);

        vm.prank(owner);
        hook.setRewardMultiplier(user, 5000); // +50%
        decreaseLiquidity(user, liquidityAmount);
        assertEq(rToken.balanceOf(user), 518400000);
    }

    function calculateTicks(uint256 rangePercent) internal view returns(int24 lowerTick, int24 upperTick) {
        uint256 lowerPriceMultiplier = 1000000 - rangePercent * 10000; // (1 - percentageRange/100) * 1000000;
        uint256 upperPriceMultiplier = 1000000 + rangePercent * 10000; // (1 + percentageRange/100) * 1000000;
        // Calculate sqrtPriceX96 for lower and upper prices.  Note: Division before multiplication to avoid overflow.
        uint160 sqrtLowerPriceX96 = uint160((uint256(SQRT_PRICE_1_1) * lowerPriceMultiplier) / 1000000);
        uint160 sqrtUpperPriceX96 = uint160((uint256(SQRT_PRICE_1_1) * upperPriceMultiplier) / 1000000);
        // Convert sqrtPriceX96 to ticks using TickMath
        int24 lowerTickPrecise = TickMath.getTickAtSqrtPrice(sqrtLowerPriceX96);
        int24 upperTickPrecise = TickMath.getTickAtSqrtPrice(sqrtUpperPriceX96);
        // Round to the nearest tick spacing
        lowerTick = (lowerTickPrecise / tickSpacing) * tickSpacing; // Integer division rounds down
        upperTick = ((upperTickPrecise + tickSpacing - 1) / tickSpacing) * tickSpacing; 
    }
    
    function provideLiquidity(address who, uint256 rangePercent, uint128 liquidityAmount) public { 
        approvePosmFor(who);
    
        (int24 lowerTick, int24 upperTick) = calculateTicks(rangePercent);

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(lowerTick),
            TickMath.getSqrtPriceAtTick(upperTick),
            liquidityAmount
        );

        IERC20(Currency.unwrap(currency0)).transfer(who, type(uint128).max);
        IERC20(Currency.unwrap(currency1)).transfer(who, type(uint128).max);

        vm.startPrank(who);
        (tokenId,) = posm.mint(
            key,
            lowerTick,
            upperTick,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            who,
            block.timestamp,
            ZERO_BYTES
        );
      
        vm.stopPrank();
    }

    function increaseLiquidity(address who, uint128 liquidityAmount) internal {
        vm.startPrank(who);

        posm.increaseLiquidity(
            tokenId,
            liquidityAmount,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            MAX_SLIPPAGE_ADD_LIQUIDITY,
            block.timestamp,
            ZERO_BYTES
        );
        vm.stopPrank();
    }

    function decreaseLiquidity(address user, uint128 liquidityAmount) public {
        vm.startPrank(user);
         posm.decreaseLiquidity(
            tokenId,
            liquidityAmount, // liquidityToRemove
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            user,
            block.timestamp,
            abi.encode(user)
        );
        vm.stopPrank();
    }

}
