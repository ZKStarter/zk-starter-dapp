// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../contracts/Staker.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../contracts/ZKSTR.sol";

contract StakerTest is Test {
    Staker public staker;
    ZKSTR public token;

    address public user1;
    address public user2;

    function setUp() public {
        // Create test users
        user1 = vm.addr(1);
        user2 = vm.addr(2);

        // Fund test users with some ether
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Deploy ERC20 token and allocate some tokens to users
        token = new ZKSTR(10000 ether);
        token.transfer(user1, 100 ether);
        token.transfer(user2, 100 ether);

        // Deploy Staker contract
        staker = new Staker(address(token));
    }

    function check_stake(address user, uint256 _amountStaked, _lockedAt,_lockedFor,_lastClaimTime) public{
        (uint256 amountStaked, lockedAt , lockedFor, lastClaimTime ) = staker.getUserStakeDetails(user1);
        assertEq(amountStaked, _amountStaked);
        assertEq(lockedAt, _lockedAt);
        assertEq(lockedFor, _lockedFor);
        assertEq(lastClaimTime, _lastClaimTime);
    }

    function testStake() public {
        // User1 stakes tokens
        vm.prank(user1);
        token.approve(address(staker), 50 ether);
        vm.prank(user1);
        staker.stake(1 ether, 30 days);

        // Check staked balance
        check_stake(user1, 1 ether, block.timestamp, 30 days, 0);

        // stake again for 30 days, ensure time is slightly more, amount is added and duration is same
        vm.prank(user1);
        staker.stake(1 ether, 30 days);
        check_stake(user1, 2 ether, block.timestamp, 30 days, 0);

        // increase stake, with increased duration
        vm.prank(user1);
        staker.stake(1 ether, 60 days);
        check_stake(user1, 3 ether, block.timestamp, 60 days, 0);

        // Expect the transaction to revert with an error
        vm.expectRevert("InvalidDuration(uint256)");
        vm.prank(user1);
        staker.stake(1 ether, 59 days);
        check_stake(user1, 3 ether, block.timestamp, 60 days, 0); //these values remain the same

        // must revert when try to stake for less duration than previous duration
        vm.expectRevert("InvalidDuration(uint256)");
        vm.prank(user1);
        staker.stake(1 ether, 30 days);
        check_stake(user1, 3 ether, block.timestamp, 60 days, 0); //these values remain the same
    }

    function testUnstake() public {
        // User2 stakes tokens
        vm.prank(user2);
        token.approve(address(staker), 50 ether);
        vm.prank(user2);
        staker.stake(50 ether, 30 days);

        // Fast forward time to allow unstaking without penalty
        vm.warp(block.timestamp + 30 days);

        // User2 unstakes tokens
        vm.prank(user2);
        staker.unstake(50 ether);

        // Check staked balance
        (uint256 amountStaked, , , ) = staker.getUserStakeDetails(user2);
        assertEq(amountStaked, 0);
    }

    function testClaimRewards() public {
        // User1 stakes tokens
        vm.prank(user1);
        token.approve(address(staker), 100 ether);
        vm.prank(user1);
        staker.stake(100 ether, 30 days);

        // Fast forward time to accumulate rewards
        vm.warp(block.timestamp + 30 days);

        // User1 claims rewards
        vm.prank(user1);
        staker.claim();

        // Check user balance to ensure rewards are added
        uint256 userBalance = token.balanceOf(user1);
        assert(userBalance > 0); // Rewards should increase user balance
    }
}