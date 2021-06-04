// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./GlobalsAndUtility.sol";

contract CYAN is GlobalsAndUtility {

    address private FLUSH_ADDR; //Address that ETH/CYN is flushed to
    uint256 public _totalBurntSupply = 0; //The total amount of CYAN burnt by everyone
    uint256 public deployBlockTimestamp; //Unix time of when the contract was deployed
    uint256 public deployBlockInterval; // deployBlockTimestamp / INTEREST_INTERVAL
    uint256 public currentInterestDenominator; //The reciprocal of the current interval interest rate
    uint256 public burnStartDay; //The first day of the first interest interval.

    //Information stored for each address
    mapping (address => uint256) public _burntBalances;
    mapping (address => uint256) public _unclaimedBalances;
    mapping (address => uint256) public _timeOfLastBurnChange;

    //Stores supply information for given interest intervals
    mapping (uint256 => uint256) public intervalsTotalSupply;
    mapping (uint256 => uint256) public intervalsTotalBurntSupply;

    event BurntCyan(address burner, uint256 amount);
    event ClaimedInterest(address claimer, uint256 amount);
    event CheckedUnclaimedBalance(address checker, address checked);
    event FlushedCYN(uint amount);
    event FlushedETH(uint amount);

    //Function that is only called once when the contract is deployed
    constructor(uint256 initialSupply, uint256 _burnStartDay) ERC20("CYAN", "CYN") {

        _mint(msg.sender, initialSupply); //ERC20 initialization function

        deployBlockTimestamp = block.timestamp;
        deployBlockInterval = block.timestamp / (INTEREST_INTERVAL);
        burnStartDay = _burnStartDay;

        FLUSH_ADDR = msg.sender; //Set ETH flush address to contract deployer

    }

    //Get how much CYAN a certain address has burnt
    function burntBalanceOf(address account) public view returns (uint256) {
        return _burntBalances[account];
    }

    //Get the unclaimed balance of a certain address. Requires gas.
    //There are only minor differences between calling this function and "updateUnclaimedBalance()"
    //Differences: This function check if current time is pre burn period. This function also called the CheckUnclaimedBalance event.
    function unclaimedBalanceOf(address account) public returns (uint256) {

        //Return 0 if burn start time is still in the future
        if ((block.timestamp / (BURN_TIME_UNIT)) < burnStartDay) {
            return 0;
        }
        else {

            updateUnclaimedBalance(account);
            CheckedUnclaimedBalance(msg.sender, account);
            return _unclaimedBalances[account];

        }

    }

    //Probably the most complicated function in the CYAN contract
    //Updates the unclaimed balance of a given address/user
    function updateUnclaimedBalance(address account) internal {

        uint256 currentTime = (block.timestamp / (INTEREST_INTERVAL)); //Get current interval

        updateIntervals(currentTime); //Update interval data

        //Initialize some loop variables
        uint256 amountToAddToBalance = 0; //Interest from all intervals combined
        uint256 lastAmount = 0; //Keeps track of how much was added for last interval's calculation

        //Set time of last burn change to now if it is not already set
        if (_timeOfLastBurnChange[account] == 0) {
            _timeOfLastBurnChange[account] = block.timestamp / (INTEREST_INTERVAL);
        }

        if (currentTime - _timeOfLastBurnChange[account] > 0) { // Checks if it has been 1 or more intervals since last unclaimed balance update

            for (uint256 i = _timeOfLastBurnChange[account]; i < currentTime; i++) { //Runs 1 iteration for every interval since last unclaimed balance update

                if (intervalsTotalBurntSupply[i] > 0) { //Checks if anybody burnt or claimed CYAN during interval "i"

                    if (intervalsTotalSupply[i] > 0) {

                        uint256 thisIntervalDenominator =  (INTEREST_MULTIPLIER * intervalsTotalBurntSupply[i]) / intervalsTotalSupply[i]; //Get the reciprocal of interval "i" interest rate. This uses the weekly interest equation seen in the green paper and blue paper.

                        if (thisIntervalDenominator < 1) {

                            lastAmount = _burntBalances[account]; //Maximum weekly interest is 100%;
                            amountToAddToBalance += lastAmount;

                        }

                        else if (thisIntervalDenominator < MINIMUM_INTEREST_DENOMINATOR) { //Check if current equation interest is greater than minimum interest.

                            lastAmount = _burntBalances[account] / thisIntervalDenominator; //Divide by reciprocal is same as multiplying by interest rate
                            amountToAddToBalance += lastAmount;

                            continue;

                        }

                        //Use minimum interest if equation interest is less.
                        else {

                            lastAmount = _burntBalances[account] / MINIMUM_INTEREST_DENOMINATOR;
                            amountToAddToBalance += lastAmount;

                            continue;

                        }

                    }

                    else {

                        //Use minimum interest if equation interest is less.
                        lastAmount = _burntBalances[account] / MINIMUM_INTEREST_DENOMINATOR;
                        amountToAddToBalance += lastAmount;

                        continue;

                    }

                }

                else { //If nobody burnt or claimed any CYAN during interval "i", the ratio will be the same as interval "i" - 1, so we can just add lastAmount to amountToAddToBalance

                    amountToAddToBalance += lastAmount;

                    //Since none was burnt or claimed, total supplies are same as last interval
                    intervalsTotalSupply[i] = intervalsTotalSupply[i - 1];
                    intervalsTotalBurntSupply[i] = intervalsTotalBurntSupply[i - 1];

                    continue;

                }

            }

        }

        _unclaimedBalances[account] += amountToAddToBalance; //Update the uncaimed balance
        _timeOfLastBurnChange[account] = currentTime; //Change the last update time

    }

    //Second most complicated function
    //Allows user to burn cyan
    function burnCyan(uint256 amount) public {

        require ((block.timestamp / (BURN_TIME_UNIT)) >= burnStartDay, "Cyan can not be burned yet. Try again on or after the burn start day."); //Check that current time is not before the burn start time.
        require (amount >= minBurnAmount, "You have not entered an amount greater than or equal to the minimum."); //Check if user is trying to burn at least the minimum burn amount.
        require (_balances[msg.sender] >= amount, "You have attempted to burn more CYAN than you own."); //Check if user has enough CYAN to burn.

        //Set time of last burn change to now if it is not already set
        if (_timeOfLastBurnChange[msg.sender] == 0) {
            _timeOfLastBurnChange[msg.sender] = block.timestamp / (INTEREST_INTERVAL);
        }

        //Update balances
        _balances[msg.sender] -= amount;
        updateUnclaimedBalance(msg.sender);
        _burntBalances[msg.sender] += amount;

        //Update total supplies
        _totalSupply -= amount;
        _totalBurntSupply += amount;
        updateIntervals(block.timestamp / (INTEREST_INTERVAL)); //Update supplies for this interval

        BurntCyan(msg.sender, amount); //Call burnt cyan event

    }

    //Allows user to add their unclaimed balance to their balance.
    function claimInterest() public returns (uint256) {

        require ((block.timestamp / (BURN_TIME_UNIT)) > burnStartDay, "It is before the burn start time"); //Make sure burning has started.
        require (_burntBalances[msg.sender] > 0, "You have no burnt CYAN."); //Only let them claim if they have burnt CYAN.

        updateUnclaimedBalance(msg.sender); //Update the unclaimed balance
        _balances[msg.sender] += _unclaimedBalances[msg.sender]; //Add unclaimed CYAN to balance
        _totalSupply += _unclaimedBalances[msg.sender]; //Update total supply
        intervalsTotalSupply[(block.timestamp - deployBlockTimestamp) / (INTEREST_INTERVAL)] += _unclaimedBalances[msg.sender]; //Update total supply without updating burnt supply

        ClaimedInterest(msg.sender, _unclaimedBalances[msg.sender]);

        uint256 amountClaimed = _unclaimedBalances[msg.sender];
        _unclaimedBalances[msg.sender] = 0; //Reset unclaimed balance

        return amountClaimed;

    }

    //Sets total supplies of given interval to current total supplies
    function updateIntervals(uint256 interval) internal {

        intervalsTotalSupply[interval] = _totalSupply;
        intervalsTotalBurntSupply[interval] = _totalBurntSupply;

        updateCurrentInterestDenominator();

    }

    //Updates the vallu of currentInterestDenominator
    function updateCurrentInterestDenominator() internal {

        uint256 timeNow = block.timestamp / (INTEREST_INTERVAL); //Use some memory so division doesn't need to happen twice.
        uint256 currentInterestEquation = (INTEREST_MULTIPLIER * intervalsTotalBurntSupply[timeNow]) / intervalsTotalSupply[timeNow];

        if (currentInterestEquation < 1) {
            currentInterestDenominator = 1;
        }
        else {
            currentInterestDenominator = currentInterestEquation;
        }

    }

    //Send ETH that is trapped in the contract to the flush address
    function flushETH() external {

        require(address(this).balance != 0, "Currently no ETH in CYAN.");

        uint256 bal = address(this).balance;
        payable(FLUSH_ADDR).transfer(bal);

        FlushedETH(bal);

    }

    //Send CYN that is trapped in the contract to the flush address
    function flushCYN() public {

        FlushedCYN(balanceOf(address(this)));
        _transfer(address(this), FLUSH_ADDR, balanceOf(address(this)));

    }

    //Backup functions
    receive() external payable {}
    fallback() external payable {}

}
