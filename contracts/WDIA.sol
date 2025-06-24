// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint);
    function approve(address spender, uint amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

contract WDIA is IERC20 {
    string public name = "Wrapped DIA";
    string public symbol = "DIA";
    uint8 public decimals = 18;

    error ZeroDepositAmount();
    error ZeroWithdrawalAmount();
    error InsufficientBalance();
    error ZeroAddress();
    error InsufficientAllowance();
    error NonEmptyCalldata();

    event Deposit(address indexed dst, uint wad);
    event Withdrawal(address indexed src, uint wad);

    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    receive() external payable {
        deposit();
    }

    fallback() external payable {
        if (msg.data.length > 0) revert NonEmptyCalldata();
        deposit();
    }

    function deposit() public payable {
        if (msg.value == 0) revert ZeroDepositAmount();
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint wad) public {
        if (wad == 0) revert ZeroWithdrawalAmount();
        if (balanceOf[msg.sender] < wad) revert InsufficientBalance();
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
        emit Transfer(msg.sender, address(0), wad);
    }

    function totalSupply() public view returns (uint) {
        return address(this).balance;
    }

    function approve(address guy, uint wad) public returns (bool) {
        if (guy == address(0)) revert ZeroAddress();
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        if (dst == address(0)) revert ZeroAddress();
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(
        address src,
        address dst,
        uint wad
    ) public returns (bool) {
        if (src == address(0)) revert ZeroAddress();
        if (dst == address(0)) revert ZeroAddress();
        if (balanceOf[src] < wad) revert InsufficientBalance();

        if (src != msg.sender && allowance[src][msg.sender] != type(uint).max) {
            if (allowance[src][msg.sender] < wad)
                revert InsufficientAllowance();
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }

    function increaseAllowance(address guy, uint wad) public returns (bool) {
        if (guy == address(0)) revert ZeroAddress();
        uint currentAllowance = allowance[msg.sender][guy];

        allowance[msg.sender][guy] = currentAllowance + wad;
        emit Approval(msg.sender, guy, allowance[msg.sender][guy]);
        return true;
    }

    function decreaseAllowance(address guy, uint wad) public returns (bool) {
        if (guy == address(0)) revert ZeroAddress();
        uint currentAllowance = allowance[msg.sender][guy];
        if (currentAllowance < wad) revert InsufficientAllowance();

        allowance[msg.sender][guy] = currentAllowance - wad;
        emit Approval(msg.sender, guy, allowance[msg.sender][guy]);
        return true;
    }
}
