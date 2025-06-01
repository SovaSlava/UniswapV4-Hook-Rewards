// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Position} from "v4-core/src/libraries/Position.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Owned} from "solmate/src/auth/Owned.sol";

contract LiquidityRewardHook is BaseHook, Owned {

    using StateLibrary for IPoolManager;
    using SafeCast for uint256;

    /// @notice Minimum accumulated liquidity amount for reward. It is current value.
    uint256 public minAccLiquidityForReward;

    /// @notice Reward rate per liquidity 
    uint256 public rewardRatePerAccLiquidity;

    uint256 constant public BASIS_POINTS = 10000;

    struct LiquidityPosition {
        uint256 liquidity;              
        uint256 lastUpdateTimestamp;   
        uint256 accumulatedLiquidityTime; 
        uint256 minTimeElapsed;
        uint256 minLqAmount;
        uint256 rewardRatePerAccLiquidity;
    }

    /// @notice Track reward multiplier of users 
    mapping(address => uint256) public multiplier;

    /// @notice Positio key => Liquidity position data
    mapping(bytes32 => LiquidityPosition) public positions;

    /// @notice Is pool allowed 
    mapping(PoolId => bool) public allowedPools;
    
    /// @notice ERC20 reward token
    address public immutable rewardToken;

    event RewardMultiplierChanged(address indexed lp, uint256 oldMultiplier, uint256 newMultiplier);
    event MinLqAmountChanged(uint256 oldValue, uint256 newValue);
    event AllowedPoolChanged(PoolId indexed poolId, bool oldValue, bool newValue);
    event MinAccLiqiudityForRewardChanged(uint256 oldValue, uint256 newValue);
    event RewardRateChanged(uint256 oldValue, uint256 newValue);
    event CantMintReward(address indexed user, bytes reason);
    event Reward(address indexed user, uint256 amount);

    /**  
     * @param poolManager_ Address of pool manager
     * @param hookOwner Hook's owner address 
     * @param token ERC20 token for reward LPs
     * @param minAccLiquidity_ Minimul accumulated liquidity for reward
     * @param rewardRatePerAccLiquidity_ Reward rate for accumulated liquidity
    */
    constructor(
        IPoolManager poolManager_, 
        address hookOwner,
        address token,
        uint256 minAccLiquidity_,
        uint256 rewardRatePerAccLiquidity_) BaseHook(poolManager_) Owned(hookOwner) {
        rewardToken = token;
        minAccLiquidityForReward = minAccLiquidity_;
        rewardRatePerAccLiquidity = rewardRatePerAccLiquidity_;
    }

     function setRewardMultiplier(address lp, uint256 m) external onlyOwner {
        emit RewardMultiplierChanged(lp, multiplier[lp], m);
        multiplier[lp] = m;
    }

    function setAllowedPool(PoolId poolId, bool value) external onlyOwner {
        emit AllowedPoolChanged(poolId, allowedPools[poolId], value);
        allowedPools[poolId] = value;
    }

    function setMinAccLiquidityForReward(uint256 minAccLiquidityForReward_) external onlyOwner {
        emit MinAccLiqiudityForRewardChanged(minAccLiquidityForReward, minAccLiquidityForReward_);
        minAccLiquidityForReward = minAccLiquidityForReward_;
    }

    function setRewardRatePerAccLiquidity(uint256 rewardRatePerAccLiquidity_) external onlyOwner {
        emit RewardRateChanged(rewardRatePerAccLiquidity, rewardRatePerAccLiquidity_);
        rewardRatePerAccLiquidity = rewardRatePerAccLiquidity_;     
    }

     /**
     * Set the hooks permissions, specifically `afterAddLiquidity` and  `afterRemoveLiquidity`
     *
     * @return permissions The permissions for the hook.
     */
    function getHookPermissions() public pure virtual override returns (Hooks.Permissions memory permissions) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @dev Hooks into the `afterAddLiquidity` hook to update accumulated liqiudity data and store block timestamp
     */
    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) internal virtual override returns (bytes4, BalanceDelta) {
        PoolId id = key.toId();
        bytes32 positionKey = Position.calculatePositionKey(sender, params.tickLower, params.tickUpper, params.salt);
        uint128 liquidity = poolManager.getLiquidity(id);

        if(allowedPools[id]) {
            LiquidityPosition storage pos = positions[positionKey];

            bool newPosition = pos.lastUpdateTimestamp == 0 ? true : false;
            update(pos, liquidity, newPosition);    
        }

        return (this.afterAddLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    /**
     * @dev Hooks into the `afterRemoveLiquidity` hook to calculate reward
     */
    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta,
        BalanceDelta,
        bytes calldata hookData
    ) internal virtual override returns (bytes4, BalanceDelta) {
        PoolId id = key.toId();
        bytes32 positionKey = Position.calculatePositionKey(sender, params.tickLower, params.tickUpper, params.salt);
        LiquidityPosition storage pos = positions[positionKey];
        
        if(allowedPools[id] || pos.lastUpdateTimestamp != 0 ) {
            
            uint128 liquidity = poolManager.getLiquidity(id);
            update(pos, liquidity, false);

            uint256 rewardAmount = pos.accumulatedLiquidityTime * pos.rewardRatePerAccLiquidity;
            address user = abi.decode(hookData, (address));
         
            if(rewardAmount >= minAccLiquidityForReward) {
                
                if(multiplier[user] > 0) {
                    rewardAmount += rewardAmount * multiplier[user] / BASIS_POINTS;
                }
                pos.accumulatedLiquidityTime = 0;
                (bool success, bytes memory reason) = rewardToken.call(abi.encodeWithSelector(0x40c10f19, user, rewardAmount));

                if(success) emit Reward(user, rewardAmount);
                else emit CantMintReward(user, reason);
            }

        }
        
        return (this.afterRemoveLiquidity.selector, BalanceDeltaLibrary.ZERO_DELTA);
    }

    function update(LiquidityPosition storage pos, uint128 liquidity, bool isNew) internal {
        if(isNew) {
            pos.rewardRatePerAccLiquidity = rewardRatePerAccLiquidity;
        }
        else {
            uint256 timeElapsed = block.timestamp - pos.lastUpdateTimestamp;
            if(timeElapsed != 0) {
                pos.accumulatedLiquidityTime += pos.liquidity * timeElapsed;
            }
        }
        pos.liquidity = liquidity / 1 ether;
        pos.lastUpdateTimestamp = block.timestamp;
    }
}