// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {StakingRewards, IERC20} from "src/Staking.sol";
import {MockERC20} from "test/MockErc20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address dso = makeAddr("dso");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(address(stakingToken), address(rewardToken));
        vm.stopPrank();
    }

    function test_alwaysPass() public view {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(address(staking.stakingToken()), address(stakingToken), "Wrong staking token address");
        assertEq(address(staking.rewardsToken()), address(rewardToken), "Wrong reward token address");

        assertTrue(true);
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);

        // we are expecting a revert if we deposit/stake zero
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(staking.totalSupply(), _totalSupplyBeforeStaking + 5e18, "totalsupply didnt update correctly");
    }

    function test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(staking.balanceOf(bob), userStakebefore - 2e18, "Balance didnt update correctly");
        assertLt(staking.totalSupply(), totalSupplyBefore, "total supply didnt update correctly");
    }

    function test_notify_Rewards() public {
        // check that it reverts if non owner tried to set duration
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        // simulate owner calls setReward successfully
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        // log block.timestamp
        console.log("current time", block.timestamp);
        // move time foward
        vm.warp(block.timestamp + 200);
        // notify rewards
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);

        // trigger revert
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);

        // trigger second revert
        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        // trigger first type of flow success
        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether) / uint256(1 weeks));
        assertEq(staking.finishAt(), uint256(block.timestamp) + uint256(1 weeks));
        assertEq(staking.updatedAt(), block.timestamp);

        // trigger setRewards distribution revert
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);
        vm.stopPrank();
    }

    function test_getReward_0() public {
        vm.startPrank(owner);
        uint256 currentReward = staking.rewards(owner);
        assertEq(currentReward, 0, "Rewards can't be greater than zero before staking");
        vm.stopPrank();
    }

    function test_getReward_not0() public {
        test_can_stake_successfully();
        uint256 initialRewardEarned = staking.earned(bob);

        deal(address(rewardToken), owner, 100 ether);

        vm.startPrank(owner);
        rewardToken.transfer(address(staking), 100 ether);
        staking.setRewardsDuration(1 weeks);

        staking.notifyRewardAmount(100 ether);

        vm.stopPrank();
        vm.warp(block.timestamp + 5 days);

        uint256 newRewardEarned = staking.earned(bob);

        assertGt(newRewardEarned, initialRewardEarned, "Reward earned not updated accordinly");
    }

    function test_reward_per_token_0() public view {
        uint256 rewardPerToken = staking.rewardPerToken();

        assertEq(rewardPerToken, 0, "Issues with reward per token update");
    }

    function test_reward_per_token_not_0() public {
        test_can_stake_successfully();
        deal(address(rewardToken), owner, 200 ether);
        vm.startPrank(owner);
        rewardToken.transfer(address(staking), 100 ether);
        staking.setRewardsDuration(1 weeks);

        staking.notifyRewardAmount(100 ether);

        vm.stopPrank();
        vm.warp(block.timestamp + 5 days);

        uint256 reward_rate_ = staking.rewardRate();
        uint256 reward_stored = staking.rewardPerTokenStored();
        uint256 total_supply_ = staking.totalSupply();
        uint256 updated_at_ = staking.updatedAt();
        uint256 last_time = staking.lastTimeRewardApplicable();
        uint256 reward_per_token = reward_stored + (last_time - updated_at_) * 1e18 / total_supply_;

        assertGt(reward_rate_, 0, "Reward rate failed to update");
        assertGt(reward_per_token, 0, "There's a problem with reward per token calculation");
    }
}