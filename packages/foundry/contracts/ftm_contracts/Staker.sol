// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//TODO: implement APR
contract Staker is Context, Ownable {
    using Address for address;
    using SafeERC20 for IERC20;

    enum Duration {
        Days_30,f
        Days_60,
        Days_90,
        Days_180
    }

    IERC20 _token;
    mapping(address => uint256) _balances;
    mapping(address => uint256) _lockTime;
    mapping(address => uint256) _lockDuration;
    uint256[] _multipliers; // [10, 15, 20, 35]
    uint256[] _aprs; //different APRs for different stake duration
    uint256 reward_balance; //also add penalized tokens to reward balance
    bool halted;

    event Stake(
        address indexed account,
        uint256 timestamp,
        uint256 duration,
        uint256 value
    );
    event Unstake(address indexed account, uint256 timestamp, uint256 value);
    event RewardsFunded(address indexed funder, uint256 amount);
    //TODO: make sure of the distinction between factory and our multisig as owner
    constructor(address _tokenAddress) Ownable(_msgSender()) {
        _token = IERC20(_tokenAddress);
        _multipliers = [10, 15, 20, 35]; //default multipliers of 1x,1.5x,2x and 3.5x
        _aprs = [100,300,500,700] //default APR values for different stake durations [1%,3%,5%,7%]
    }

    function stakedBalance(address account) external view returns (uint256) {
        return _balances[account];
    }


    /**
     * @dev Fund the contract to reward stakers, can be funded by anyone
     * @notice - Access control: External
     */
    function fund_rewards(uint256 amount) external {
        _token.safeTransferFrom(_msgSender(), address(this), amount);
        reward_balance += amount;
        emit RewardsFunded(_msgSender(), amount)
    }


    /**
     * @dev Get the unlock time of user tokens based on their lock time and total lock duration
     * @notice - Access control: External.
     * @return - time at which user tokens will be unlocked
     */
    function unlockTime(address account) public view returns (uint256) {
        return _lockTime[account] + _lockDuration[account];
    }

    function duration_to_time(Duration duration) public pure returns (uint256) {
        if (duration == Duration.Days_30) {
            return 30 days;
        } else if (duration == Duration.Days_60) {
            return 60 days;
        } else if (duration == Duration.Days_90) {
            return 90 days;
        } else if (duration == Duration.Days_180) {
            return 180 days;
        }
        revert("Invalid duration");
    }

    /**
     * @dev Stakes and locks the token for the given duration
     * @notice - Access control: External. Can only be called when app is nothalted
     */
    function stake(uint256 value, Duration duration) external notHalted {
        require(value > 0, "stake value should be greater than 0");
        uint256 duration_time = duration_to_time(duration);

        // if the user tokens are not unlocked, then enforce that their stake duration is greater or equal to current duration
        if (!unlockTime(_msgSender()) <= block.timestamp) {
            require(
                duration_time >= _lockDuration[_msgSender()],
                "new duration must be greater or equal to previous"
            );
        }

        uint256 unlock_time = duration_time + block.timestamp; // x number of days from now

        //allows locking if the new time is more than previous locked time
        if (unlock_time > unlockTime(_msgSender())) {
            //perform staking and locking
            _token.safeTransferFrom(_msgSender(), address(this), value);
            _balances[_msgSender()] += value;
            _lockTime[_msgSender()] = block.timestamp; //TODO: if user stakes more in future, the time would get reset, do we need this?
            _lockDuration[_msgSender()] = duration_time;

            emit Stake(_msgSender(), block.timestamp, duration_time, value);
        } else {
            revert("new duration cannot be less than previous duration");
        }
    }
    
        /**
     * @dev Stakes and locks the token for the given duration
     * @notice - Access control: External. Can only be called when app is nothalted
     */
    
    function unstake(uint256 value) external {
        require(_balances[_msgSender()] >= value, "Staker: insufficient balance");

        uint256 lockStartTime = _lockTime[_msgSender()];
        uint256 lockDuration = _lockDuration[_msgSender()];
        uint256 currentTime = block.timestamp;
        uint256 unlockTime = lockStartTime + lockDuration;

        require(currentTime >= lockStartTime, "Staker: invalid current time");

        uint256 unstakeAmount = value;
        if (currentTime < unlockTime) {
            uint256 halfDuration = lockStartTime + (lockDuration / 2);
            if (currentTime <= halfDuration) {
                unstakeAmount = (value * 50) / 100; // 50% reduction
            } else {
                // time staked will always be greater than halfduration because the other case is handled in if statement above
                // thus this value will not be negative or timestaked > lockDuration/2
                uint256 timeStaked = currentTime - lockStartTime;
                uint256 linearIncrease = 50 + ((50 * (timeStaked - (lockDuration / 2))) / (lockDuration / 2));
                unstakeAmount = (value * linearIncrease) / 100;
            }f
        }

        _balances[_msgSender()] -= value;
        // Add the penalty to the reward balance, this will be recycled as additional staker APR
        reward_balance += (value - unstakeAmount); 

        // if the user unstakes everything or all his tokens are unlocked and he has not received any penaly
        // reset it's duration and lock time
        if (_balances[_msgSender()] == 0 || value == unstakeAmount) {
            _lockDuration[_msgSender()] = 0;
            _lockTime[_msgSender()] = 0;
        }

        _token.safeTransfer(_msgSender(), unstakeAmount);
        emit Unstake(_msgSender(), block.timestamp, unstakeAmount);
    }



    // returns user multiplier based on lock duration. If tokens are unlocked, multiplier is 0 right now
    function user_multiplier(address account) external returns (uint256) {
        // if the user tokens are unlocked, they don't earn a multiplier
        string revertMsg = "Must lock tokens to participate";
        if (unlockTime(account) < block.timestamp) {
            revert(revertMsg);
        }

        uint256 lockDuration = _lockDuration[account];

        if (lockDuration == 30 days) {
            return _multipliers[0];
        } else if (lockDuration == 60 days) {
            return _multipliers[1];
        } else if (lockDuration == 90 days) {
            return _multipliers[2];
        } else if (lockDuration == 180 days) {
            return _multipliers[3];
        } else {
            revert(revertMsg);
        }
    }

    /**
     * @dev to set the multipliers array. add values in whole decimals
     * @notice - Access control: onlyOwner, they can change the multiplier anytime
     */
    function set_multiplier(uint256[] calldata multipliers) external onlyOwner {
        _multipliers = multipliers;
    }

    /**
     * @dev to set the aprs array, add values in multiple of 100
     * @notice - Access control: onlyOwner, they can change the APR rewards anytime
     */
    function set_APRs(uint256[] calldata aprs) external onlyOwner {
        _aprs = aprs;
    }

    function halt(bool status) external onlyOwner {
        halted = status;
    }

    /**
     * @dev to allow devs to withdraw tokens from contract in case of a hack or any issue
     * @notice - Access control: onlyOwner, 
     */
    function withdraw(uint256 value) external onlyOwner{
        _token.safeTransfer(_msgSender(),value);
    }

    // ensures that tokens are unlocked for the user
    modifier lockable() {
        require(
            unlockTime(_msgSender()) <= block.timestamp,
            "Staker: account is locked"
        );
        _;
    }

    modifier notHalted() {
        require(!halted, "Staker: Deposits are paused");
        _;
    }
}z
