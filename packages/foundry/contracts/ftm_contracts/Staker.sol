// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Staker is Context, Ownable {
    using Address for address;
    using SafeERC20 for IERC20;

    IERC20 _token;
    mapping(address => uint256) _balances;
    mapping(address => uint256) _unlockTime;
    mapping(address => bool) _isIDO;
    bool halted;

    event Stake(address indexed account, uint256 timestamp, uint256 value);
    event Unstake(address indexed account, uint256 timestamp, uint256 value);
    event Lock(
        address indexed account,
        uint256 timestamp,
        uint256 unlockTime,
        address locker
    );

    constructor(address _tokenAddress) {
        _token = IERC20(_tokenAddress);
    }

    function stakedBalance(address account) external view returns (uint256) {
        return _balances[account];
    }

    function unlockTime(address account) external view returns (uint256) {
        return _unlockTime[account];
    }

    function isIDO(address account) external view returns (bool) {
        return _isIDO[account];
    }

    function stake(uint256 value) external notHalted {
        require(value > 0, "Staker: stake value should be greater than 0");
        _token.safeTransferFrom(_msgSender(), address(this), value);

        _balances[_msgSender()] = _balances[_msgSender()] + value;
        emit Stake(_msgSender(), block.timestamp, value);
    }

    function unstake(uint256 value) external lockable {
        require(
            _balances[_msgSender()] >= value,
            "Staker: insufficient staked balance"
        );

        _balances[_msgSender()] = _balances[_msgSender()] - value;
        _token.safeTransfer(_msgSender(), value);
        emit Unstake(_msgSender(), block.timestamp, value);
    }

    function lock(address user, uint256 unlock_time) external onlyIDO {
        require(unlock_time > block.timestamp, "Staker: unlock is in the past");
        if (_unlockTime[user] < unlock_time) {
            _unlockTime[user] = unlock_time;
            emit Lock(user, block.timestamp, unlock_time, _msgSender());
        }
    }

    function halt(bool status) external onlyOwner {
        halted = status;
    }

    function addIDO(address account) external onlyOwner {
        require(account != address(0), "Staker: cannot be zero address");
        _isIDO[account] = true;
    }

    modifier onlyIDO() {
        require(_isIDO[_msgSender()], "Staker: only IDOs can lock");
        _;
    }

    modifier lockable() {
        require(
            _unlockTime[_msgSender()] <= block.timestamp,
            "Staker: account is locked"
        );
        _;
    }

    modifier notHalted() {
        require(!halted, "Staker: Deposits are paused");
        _;
    }
}
